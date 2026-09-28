#!/bin/bash
# rabbitnodefix.sh [new-node-name]
#
# Call this whenever the node name (container hostname) changes.
#
# RabbitMQ's node name is rabbit@<hostname> and its user database lives in
# /var/lib/rabbitmq/mnesia/rabbit@<hostname>. If the hostname changes while
# the broker is running, rabbitmqctl can no longer reach it (so add_user
# silently fails) and clients get "PLAIN login refused". This script:
#   1. applies the new hostname (+ /etc/hosts so Erlang can resolve it)
#   2. restarts the broker under that name if it is not already running as it
#   3. waits for it, then (re)creates the app user and permissions
#   4. verifies the login really works
#
# The new name defaults to /root/myhostname, then to the current hostname.
# Idempotent; safe to run repeatedly.

RMQ_USER=rabb_Mezo
RMQ_PASS=YousefNadody

export PATH="/opt/erlang/bin:/opt/rabbitmq/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export ELIXIR_ERL_OPTIONS="+fnu"   # silence the latin1 locale warning
export LC_ALL=C

log() { echo "[rabbitnodefix] $*"; }

# rabbitmqctl against $NODE; its stderr (locale/libtinfo noise) only shown on failure
rmq() {
    local err rc
    err=$(rabbitmqctl -n "$NODE" "$@" 2>&1 >/dev/null); rc=$?
    [ $rc -ne 0 ] && echo "$err" >&2
    return $rc
}

exec 9>/run/rabbitnodefix.lock
flock -w 300 9 || { log "another run holds the lock"; exit 1; }

NEW="${1:-$(cat /root/myhostname 2>/dev/null)}"
NEW="${NEW:-$(hostname)}"
NEW="$(echo "$NEW" | tr -d '[:space:]')"
[ -z "$NEW" ] && { log "no node name given"; exit 1; }
NODE="rabbit@$NEW"

# 1. hostname + resolvability
[ "$(hostname)" = "$NEW" ] || { log "hostname -> $NEW"; hostname "$NEW"; }
echo "$NEW" > /etc/hostname
grep -qE "^127\.0\.0\.1[[:space:]]+${NEW}([[:space:]]|$)" /etc/hosts \
    || echo "127.0.0.1 $NEW" >> /etc/hosts

# 2. restart broker unless it already answers as $NODE
if rabbitmqctl -n "$NODE" -t 10 status >/dev/null 2>&1; then
    log "broker already running as $NODE"
else
    log "broker not reachable as $NODE -> restarting it under the new name"
    # 9>&- : the broker must not inherit (and hold forever) our lock fd
    systemctl restart rabbitmq-server 9>&-
fi

# 3. wait for it, then make sure the app user exists
ok=0
for _ in $(seq 1 60); do
    if rabbitmqctl -n "$NODE" -t 10 await_startup >/dev/null 2>&1; then ok=1; break; fi
    sleep 2
done
[ $ok -eq 1 ] || { log "FAILED: $NODE did not come up (see /var/log/rabbitmq/$NODE.log)"; exit 2; }

if rabbitmqctl -n "$NODE" list_users 2>/dev/null | awk '{print $1}' | grep -qx "$RMQ_USER"; then
    rmq change_password "$RMQ_USER" "$RMQ_PASS"
else
    rmq add_user "$RMQ_USER" "$RMQ_PASS"
fi
rmq set_permissions -p / "$RMQ_USER" ".*" ".*" ".*"

# 4. verify
if rmq authenticate_user "$RMQ_USER" "$RMQ_PASS" 2>/dev/null; then
    log "OK: $NODE up, user $RMQ_USER can log in"
else
    log "FAILED: $RMQ_USER cannot authenticate on $NODE"
    exit 3
fi
