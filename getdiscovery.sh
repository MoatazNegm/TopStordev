#!/usr/bin/sh
[ -f /TopStor/flavor.sh ] && . /TopStor/flavor.sh
cd /TopStor/
echo hihi>/root/tmpgetdiscovery
etcd='10.11.11.253'
# QSD5.352 r10s (QC proof r10r3: QX-1018 tail and the first join of build 3549), container flavour: a discover request while a
# scan runs used to do nothing (and first deleted the possible/ keys of the running scan).  It now only extends the running
# scan (/TopStordata/discovery.extend, read by the loop below) and leaves its keys alone.  Physical: unchanged.
if [ -z "$GETDISCOVERY_BG" ] && is_container 2>/dev/null; then
	for pid in $(pidof -x getdiscovery.sh); do
		if [ $pid != $$ ]; then
			echo "`date +%s` $$" > /TopStordata/discovery.extend
			echo "`date '+%F %T'` getdiscovery.sh: a scan is running (PID $pid): discover asked again, the scan is extended (r10s)" >> /root/getdiscovery.log
			echo "[$(date)] : discovery.sh : Process is already running with PID $pid (scan extended)"
			exit 1
		fi
	done
fi
/TopStor/etcddel.py $etcd possible --prefix
leaderip=`docker exec etcdclient /TopStor/etcdgetlocal.py leaderip`
/TopStor/etcddel.py $leaderip possible --prefix
# The scan below runs until it is told to stop (or 600 rounds; container flavour, r10s: a wall-clock time instead, see the loop).  It is started through the node's command queue
# (topstorrecvreply.py runs one command at a time), so in the foreground it held every later command -- adding a
# user, for one -- until the scan ended.  The script therefore starts itself again detached and returns at once.
if [ -z "$GETDISCOVERY_BG" ]; then
	for pid in $(pidof -x getdiscovery.sh); do
	    if [ $pid != $$ ]; then
	        echo "[$(date)] : discovery.sh : Process is already running with PID $pid"
	        exit 1
	    fi
	done
	GETDISCOVERY_BG=1 setsid nohup /TopStor/getdiscovery.sh "$@" >/dev/null 2>&1 </dev/null &
	exit 0
fi
cd /TopStor
# the discovery etcd database is kept between scans (tojoin / ackjoin must survive a new scan);
# stale possible/ keys are deleted explicitly above and tostop is reset below
mkdir -p /TopStordata/discovery

node_device=`nmcli -g connection.interface-name connection show cmynode | head -n 1`
if [ -z "$node_device" ]; then
	echo "cmynode has no active device"
	exit 1
fi
# QSD5.352 r10s2 (validator r10s G7), container flavour: the .253 changes of cmynode run under /TopStordata/cmynode.lock like
# every other cmynode address change (cmynodeaddr.sh): a scan now ends 30 min - 2 h after its start, at any time, beside volume
# address adds or a take-over, and an unlocked 'conn modify' + 'reapply' could drop an address another script had just added.
# Physical: the same nmcli commands as before, no lock.
cmy253() {
	if is_container 2>/dev/null; then
		exec 9>>/TopStordata/cmynode.lock
		flock -w 120 9 || echo "`date '+%F %T'` getdiscovery.sh: no cmynode lock after 120 s, going on (r10s2)" >> /root/getdiscovery.log
	fi
	nmcli connection modify cmynode ${1}ipv4.addresses $etcd/24
	if [ "$1" = "+" ]; then nmcli device reapply $node_device; else nmcli device reapply $node_device 2>/dev/null; fi
	if is_container 2>/dev/null; then
		flock -u 9
		exec 9>&-
	fi
}
cmy253 +
rm -rf /TopStordata/discovery.sh
cp /TopStor/discovery.sh /TopStordata/
sed -i 's/SLEEP/sleep 10/g' /TopStordata/discovery.sh
leaderip=`docker exec etcdclient /TopStor/etcdgetlocal.py leaderip`
echo starting etcd 
docker run  --rm --name discovery --hostname discovery -v /etc/localtime:/etc/localtime:ro -v /root/gitrepo/resolv.conf:/etc/resolv.conf -p $etcd:2379:2379 -v /TopStor/:/TopStor -v /TopStordata/discovery:/default.etcd -v /TopStordata/discovery.sh:/runme.sh --net ${DOCKER_NET:-bridge0} moataznegm/quickstor:etcd  &
# the container registers in the internal DNS some seconds after it starts, longer when the node is busy (a second node
# booting): a lookup after a fixed 3 s found nothing, discovery.sh got etcdip='' , the discovery etcd never ran and the scan
# below polled a dead port for its 600 rounds while the joining node announced itself to nobody.  Wait for the answer.
newip=
for tries in `seq 1 60`
do
	newip=`docker exec intdns nslookup discovery | grep Address | grep -v 127 | awk '{print $2}'`
	[ -n "$newip" ] && break
	sleep 1
done
echo newip=$newip
if [ -z "$newip" ]; then
	echo "discovery container did not get an address in the internal DNS after 60 s, scan not started"
	docker rm -f discovery
	cmy253 -
	exit 1
fi
docker rm -f discovery
rm -rf /TopStordata/discovery.sh
cp /TopStor/discovery.sh /TopStordata/
sed -i 's/SLEEP//g' /TopStordata/discovery.sh
sed -i "s/ETCDIP/$newip/g" /TopStordata/discovery.sh
docker run  -itd --rm --name discovery --hostname discovery -v /etc/localtime:/etc/localtime:ro -v /root/gitrepo/resolv.conf:/etc/resolv.conf -p $etcd:2379:2379 -v /TopStor/:/TopStor -v /TopStordata/discovery:/default.etcd -v /TopStordata/discovery.sh:/runme.sh --net ${DOCKER_NET:-bridge0} moataznegm/quickstor:etcd
counter=0
# QSD5.352 r10s, container flavour: the scan ended after 600 rounds whatever the load; a node whose docker_setup ran 21 min
# under load (r10r3 QX-1018: announcing from 05:21, scan of 05:06 already over) announced itself to nobody (12277 'not
# reachable' lines) and the join failed.  The scan now runs DISCOVERY_SECS (default 1800 s) of wall-clock time from its start
# or from the last discover request (discovery.extend), at least 300 s more while a node is announcing (possible/ key), never
# longer than DISCOVERY_MAX (default 7200 s) in all.  Physical: the 600 rounds as before.
dsecs=${DISCOVERY_SECS:-1800}
aseconds=${DISCOVERY_ANNOUNCE_SECS:-300}
scan_t0=`date +%s`
scan_end=$((scan_t0+dsecs))
scan_max=$((scan_t0+${DISCOVERY_MAX:-7200}))
rm -f /TopStordata/discovery.extend
ext_seen=
scan_why=
if is_container 2>/dev/null; then
	echo "`date '+%F %T'` getdiscovery.sh: scan started (PID $$), ends at the latest after $dsecs s without a new discover request, $((scan_max-scan_t0)) s in all (r10s)" >> /root/getdiscovery.log
fi
# the discovery database is kept between scans, so tostop still says yes from the last one: reset it
# and make sure etcd (just started) took it, or the loop below would stop at once
for tries in `seq 1 30`
do
	./etcdput.py $etcd tostop no >/dev/null
	[ "`/TopStor/etcdget.py $etcd tostop`" = "no" ] && break
	sleep 1
done
/TopStor/etcddel.py $etcd possible --prefix
/TopStor/etcddel.py $leaderip  possible --prefix
while true
do
	if [ -z "`docker ps -q -f name=^discovery$`" ]; then
		echo "discovery container is not running, scan stopped"
		scan_why="the discovery container is gone"
		break
	fi
	lines=`/TopStor/etcdget.py $etcd possible --prefix`
	plines=$lines
	counter=$((counter+1))
	echo $lines
	lines=`/TopStor/etcdget.py $etcd tostop`'s'
	/TopStor/syncpossibles.py $leaderip $etcd
	echo $lines | grep yes
	if [ $? -eq 0 ];
	then
		scan_why="tostop yes"
		break
	fi
	if is_container 2>/dev/null; then
		now=`date +%s`
		ext=`cat /TopStordata/discovery.extend 2>/dev/null`
		if [ -n "$ext" ] && [ "$ext" != "$ext_seen" ]; then
			ext_seen=$ext
			scan_end=$((now+dsecs))
			[ $scan_end -gt $scan_max ] && scan_end=$scan_max
			echo "`date '+%F %T'` getdiscovery.sh: discover asked again after $((now-scan_t0)) s: the scan runs until +$((scan_end-scan_t0)) s (r10s)" >> /root/getdiscovery.log
		fi
		if echo "$plines" | grep -q "possible/" && [ $((now+aseconds)) -gt $scan_end ]; then
			scan_end=$((now+aseconds))
			[ $scan_end -gt $scan_max ] && scan_end=$scan_max
		fi
		if [ $now -ge $scan_end ]; then
			echo "`date '+%F %T'` getdiscovery.sh: scan ended after $((now-scan_t0)) s ($counter rounds; possible: `echo $plines | cut -c1-120`) (r10s)" >> /root/getdiscovery.log
			break
		fi
	elif [ $counter -ge 600  ];
	then
		break
	fi
	sleep 1 

done

# QSD5.352 r10s2 (validator r10s G11), container flavour: the tostop and container-gone ends are logged too (only the time end
# was), and a discover request that came in after the last round read discovery.extend (the tail below runs seconds, longer
# under load) is not lost: it was answered 'the scan is extended' and exit 1, so this scan starts a new one after its cleanup.
if is_container 2>/dev/null && [ -n "$scan_why" ]; then
	echo "`date '+%F %T'` getdiscovery.sh: scan ended after $((`date +%s`-scan_t0)) s ($counter rounds): $scan_why (r10s2)" >> /root/getdiscovery.log
fi
./etcdput.py $etcd tostop yes 
docker rm -f discovery
cmy253 -
if is_container 2>/dev/null; then
	ext=`cat /TopStordata/discovery.extend 2>/dev/null`
	if [ -n "$ext" ] && [ "$ext" != "$ext_seen" ]; then
		echo "`date '+%F %T'` getdiscovery.sh: discover was asked again while the scan ended ($ext): a new scan starts (r10s2)" >> /root/getdiscovery.log
		GETDISCOVERY_BG=1 setsid nohup /TopStor/getdiscovery.sh "$@" >/dev/null 2>&1 </dev/null &
	fi
fi

