#!/usr/bin/sh
# TopStor node-discovery helper.
# Spawns a short-lived etcd on 10.11.11.253 (or $ETCD_DISCOVERY_IP), waits for
# peer nodes to register themselves under etcd's "possible/*" keys, syncs those
# entries into the leader's etcd, and tears the temporary etcd back down.
#
# IMPORTANT: the discovery IP must NOT live on the cluster bond master
# (cmynode -> bond0 in this build). Doing so shadows the bond's real cluster
# addresses (10.11.11.242/248) and, in active-backup mode, gets caught up in
# the bond's MAC/failover management - which is exactly the symptom that
# stops other nodes from appearing in the Discovered Nodes list.
#
# Instead we attach the discovery IP to a bond SLAVE (e.g. enp0s8). The slave
# is the real NIC, so external nodes can ARP and reach 10.11.11.253, and we
# never disturb the bond's primary addresses.
#
# Overrides via env: ETCD_DISCOVERY_IP (default 10.11.11.253),
#                   ETCD_DISCOVERY_SUBNET (default 24),
#                   ETCD_DISCOVERY_TIMEOUT (default 600 seconds).
set -u

# ---- single-instance guard (PID file, robust against pidof -x false pos) ----
# The legacy `pidof -x getdiscovery.sh` check would also match parent shell
# processes (timeout, the bash -c from SSH, etc.) and cause the script to
# exit immediately. A PID file + kill -0 is unambiguous.
PIDFILE="/var/run/topstor-getdiscovery.pid"
if [ -f "$PIDFILE" ]; then
    OLD_PID=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        echo "[$(date)] getdiscovery.sh: another instance is already running (pid $OLD_PID), exiting"
        exit 1
    fi
    # stale pid file - the previous run died without cleaning up
    rm -f "$PIDFILE"
fi
echo $$ > "$PIDFILE"

cd /TopStor/

etcd="${ETCD_DISCOVERY_IP:-10.11.11.253}"
discover_subnet="${ETCD_DISCOVERY_SUBNET:-24}"
discover_timeout="${ETCD_DISCOVERY_TIMEOUT:-600}"
leaderip=""
node_device=""
added_ip=""

log() { echo "[$(date)] getdiscovery.sh: $*"; }
cleanup() {
    # Always try to undo what we did, even on failure
    [ -n "$added_ip" ] && ip address del "$etcd/$discover_subnet" dev "$node_device" 2>/dev/null
    docker rm -f discovery >/dev/null 2>&1 || true
    [ -n "$leaderip" ] && /TopStor/etcdput.py "$etcd" tostop yes >/dev/null 2>&1 || true
    rm -f "$PIDFILE"
}
trap cleanup EXIT INT TERM

# ---- discover the leader IP from the running etcd cluster -------------------
# The legacy code used `docker exec etcdclient ...`, but no such container
# exists in this build. Pull the leader from the cluster's member list instead.
find_leaderip() {
    # 1) prefer the live etcd endpoints file written by checksyncs.py
    if [ -r /pacedata/runningetcdnodes.txt ]; then
        ep=$(awk -F'"' '/clientURLs/ {gsub(/^.*http:\/\//,""); gsub(/[:,].*$/,""); print; exit}' /pacedata/runningetcdnodes.txt 2>/dev/null)
        if [ -n "$ep" ] && etcdctl --endpoints="http://$ep:2379" get leaderip --print-value-only >/tmp/_leaderip 2>/dev/null; then
            sed -i 's/[[:space:]]*$//' /tmp/_leaderip
            leaderip=$(cat /tmp/_leaderip)
            rm -f /tmp/_leaderip
            [ -n "$leaderip" ] && [ "$leaderip" != "_1" ] && return 0
        fi
    fi
    # 2) fall back to the well-known bond-IP endpoint (10.11.11.248)
    if etcdctl --endpoints="http://10.11.11.248:2379" get leaderip --print-value-only >/tmp/_leaderip 2>/dev/null; then
        sed -i 's/[[:space:]]*$//' /tmp/_leaderip
        leaderip=$(cat /tmp/_leaderip)
        rm -f /tmp/_leaderip
        [ -n "$leaderip" ] && [ "$leaderip" != "_1" ] && return 0
    fi
    leaderip=""
    return 1
}

if ! find_leaderip; then
    log "ERROR: cannot reach the cluster etcd to read 'leaderip'. Is checksyncs.py running?"
    exit 1
fi
log "leaderip=$leaderip"

# ---- pick the right interface for the discovery IP --------------------------
# cmynode is the cluster connection. In this build it is a BOND (bond0), so
# `nmcli -g connection.interface-name connection show cmynode` returns bond0.
# We must NOT add the discovery IP to the bond master - that is the bug this
# script is fixing. Instead, find an active slave of that bond and use it.
master_dev=$(nmcli -g connection.interface-name connection show cmynode 2>/dev/null | head -n 1)
if [ -z "$master_dev" ]; then
    log "ERROR: cmynode has no active device"
    exit 1
fi

if [ -d "/sys/class/net/$master_dev/bonding" ]; then
    # bond master: pick the first active slave
    slave=$(awk 'NR>1 && $0!="" {print $1; exit}' /sys/class/net/"$master_dev"/bonding/slaves 2>/dev/null)
    if [ -n "$slave" ] && [ -d "/sys/class/net/$slave" ]; then
        node_device="$slave"
        log "cmynode=$master_dev is a bond; using slave $node_device for discovery IP"
    else
        log "WARN: bond $master_dev has no active slave; falling back to master (legacy behavior)"
        node_device="$master_dev"
    fi
else
    node_device="$master_dev"
    log "cmynode interface is $node_device (not a bond)"
fi

# ---- idempotently attach the discovery IP to the chosen interface -----------
if ip addr show dev "$node_device" 2>/dev/null | grep -q " $etcd/"; then
    log "$etcd is already on $node_device; leaving it"
else
    if ! ip address add "$etcd/$discover_subnet" dev "$node_device"; then
        log "ERROR: failed to add $etcd to $node_device"
        exit 1
    fi
    added_ip="1"
    log "added $etcd/$discover_subnet to $node_device"
fi

# Always make sure the link is up
ip link set "$node_device" up 2>/dev/null || true

# ---- stage the docker etcd wrapper script ----------------------------------
rm -rf /TopStordata/discovery.sh
cp /TopStor/discovery.sh /TopStordata/
sed -i 's/SLEEP/sleep 10/g' /TopStordata/discovery.sh

log "starting placeholder etcd container"
docker run --rm --name discovery --hostname discovery \
    -v /etc/localtime:/etc/localtime:ro \
    -v /root/gitrepo/resolv.conf:/etc/resolv.conf \
    -p "$etcd":2379:2379 \
    -v /TopStor/:/TopStor \
    -v /root/discovery:/default.etcd \
    -v /TopStordata/discovery.sh:/runme.sh \
    --net bridge0 moataznegm/quickstor:etcd &
sleep 3

# ---- find the placeholder container's IP on bridge0 -------------------------
# The legacy code called `docker exec intdns nslookup discovery`, but the
# intdns container no longer exists. `docker inspect` is the supported way.
newip=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
    newip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' discovery 2>/dev/null | head -n 1)
    [ -n "$newip" ] && break
    sleep 1
done
log "placeholder etcd IP on bridge0: ${newip:-<none>}"

docker rm -f discovery >/dev/null 2>&1 || true

if [ -z "$newip" ]; then
    log "ERROR: discovery container has no IP on bridge0; aborting"
    exit 1
fi

# ---- run the real etcd container -------------------------------------------
rm -rf /TopStordata/discovery.sh
cp /TopStor/discovery.sh /TopStordata/
sed -i 's/SLEEP//g' /TopStordata/discovery.sh
sed -i "s/ETCDIP/$newip/g" /TopStordata/discovery.sh

log "starting real etcd container (listen=$newip, published on host $etcd)"
docker run -itd --rm --name discovery --hostname discovery \
    -v /etc/localtime:/etc/localtime:ro \
    -v /root/gitrepo/resolv.conf:/etc/resolv.conf \
    -p "$etcd":2379:2379 \
    -v /TopStor/:/TopStor \
    -v /root/discovery:/default.etcd \
    -v /TopStordata/discovery.sh:/runme.sh \
    --net bridge0 moataznegm/quickstor:etcd

# ---- poll for "possible" entries and sync to the leader etcd ---------------
counter=0
/TopStor/etcdput.py "$etcd" tostop no >/dev/null 2>&1
/TopStor/etcddel.py "$etcd" possible --prefix >/dev/null 2>&1
/TopStor/etcddel.py "$leaderip" possible --prefix >/dev/null 2>&1

log "polling for discovered nodes (timeout=${discover_timeout}s)"
while [ "$counter" -lt "$discover_timeout" ]; do
    /TopStor/etcdget.py "$etcd" possible --prefix >/dev/null 2>&1
    counter=$((counter+1))
    tostop=$(/TopStor/etcdget.py "$etcd" tostop 2>/dev/null)
    /TopStor/syncpossibles.py "$leaderip" "$etcd" >/dev/null 2>&1
    case "$tostop" in
        *yes*) log "tostop=yes after ${counter}s; finishing"; break ;;
    esac
    sleep 1
done

if [ "$counter" -ge "$discover_timeout" ]; then
    log "timed out after ${discover_timeout}s; finishing"
fi

# trap will clean up the IP and the container
