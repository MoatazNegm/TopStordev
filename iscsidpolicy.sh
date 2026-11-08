#!/bin/bash
# iscsidpolicy.sh tick      -- CONTAINER flavour only; called every 3 s by the node's iscsi guardian
#                              (/usr/local/sbin/iscsi-guardian.sh, written by the node entrypoint; old entrypoints that do
#                              not call it keep their old behaviour: start iscsid whenever none runs here).
# iscsidpolicy.sh state     -- print this node's state (fit|booting|unfit) and the reason, for tests and people
#
# QSD5.352 r10c (QC proof E-2, high).  All node containers share the host kernel and ONE iscsid (one abstract socket
# @ISCSIADM_ABSTRACT_NAMESPACE in the host network namespace, see /TopStor/iscsidowner.sh).  The guardian of every node
# started iscsid as soon as none ran, so on 2026-11-08 06:56, when the holder zfs2 stopped, the guardian of zfs1 took it
# although zfs1's stack was down (its docker_setup waited for an etcd that had exited: E-1).  zfs1 never logged in to
# any target; when zfs2 came back its iscsid was refused ("another iscsid already owns ...") and its iscsirefresh.sh did
# nothing ("owned by another container"): nobody logged in, the pools could not be imported.
#
# Rules (one tick):
#   1. A node starts iscsid only when the socket is free AND the node is not unfit.
#   2. A node that wants iscsid (not unfit, socket held by another container) says so: it holds an abstract unix socket
#      @TOPSTOR_ISCSID_WANT_<host> in the host network namespace (a small listener, pid in /run/iscsidwant.pid; r10e: the
#      listener is found by that name, the pid file is only a copy).
#   3. The holder releases iscsid (SIGTERM: sessions stay in the kernel, the next iscsid takes them over) only when it is
#      unfit AND another node wants it.  An unfit holder with nobody waiting keeps it (an iscsid with no logins of its own
#      still recovers the existing sessions).  A fit holder never releases.
#   4. After it owns iscsid, a node drops its own want listener.
# A node is UNFIT when its docker_setup failed (/root/dockersetup.failed, written when etcd does not start), or when it
# has no etcd container running and no docker_setup / image preload running (or the docker_setup runs for more than
# 30 min without etcd), once the container has been up for 5 min.  BOOTING (counts as fit): the first 5 min, an image
# preload, or a docker_setup run (up to 30 min).  FIT: etcd runs (r10d: and a heartbeat / zfsping looper lives; etcd
# without loopers and without a docker_setup is UNFIT).
[ -f /TopStor/flavor.sh ] && . /TopStor/flavor.sh
is_container 2>/dev/null || exit 0
HNS=/host-ns/net
if [ -e "$HNS" ]; then NSE="nsenter --net=$HNS"; else NSE=""; fi
ME=${ISCSIDPOLICY_ME:-`hostname -s`}   # the override is for tests
LOG=${ISCSIDPOLICY_LOG:-/var/log/iscsid.log}
STATEF=/run/iscsidpolicy.last
WANTPID=/run/iscsidwant.pid
WANTNAME="TOPSTOR_ISCSID_WANT_$ME"
GRACE=${ISCSIDPOLICY_GRACE:-300}
SETUPMAX=${ISCSIDPOLICY_SETUPMAX:-1800}
UNFITMIN=${ISCSIDPOLICY_UNFITMIN:-60}    # a holder releases only after being unfit this long (an etcd restart of a take-over
                                         # by docker_primary.sh leaves a few seconds without an etcd container)
UNFITF=/run/iscsidpolicy.unfitsince
LOOPERS=${ISCSIDPOLICY_LOOPERS:-'/pace/(heartbeatlooper\.sh|heartbeat\.py|zfsping\.py)'}

say() {   # log a line only when it differs from the last one (the guardian runs every 3 s)
	[ "`cat $STATEF 2>/dev/null`" = "$*" ] && return 0
	echo "$*" > $STATEF
	echo "`date '+%F %T'` iscsidpolicy $ME: $*" >> $LOG
}
unixsockets() { $NSE cat /proc/net/unix 2>/dev/null; }
sockettaken() { unixsockets | grep -q '@ISCSIADM_ABSTRACT_NAMESPACE'; }
mine() { pgrep -x iscsid >/dev/null 2>&1; }
otherwants() { unixsockets | grep -o '@TOPSTOR_ISCSID_WANT_[^ ]*' | grep -v "@$WANTNAME\$" | head -1; }
# r10d (validator 10c D4): the container's /run is no tmpfs, so the pid file survives a container restart and its pid
# may then belong to ANY process (pids start again from 1): kill -0 alone made a holder kill an unrelated process and a
# fit node never ask.  The pid counts only while its command line holds this node's want-socket name.  (The entrypoint
# also removes /run/iscsidwant.pid and /run/iscsidpolicy.* before it starts the guardian.)
# r10e (validator 10d D7): the listener is found by its socket name, not only through the pid file.  When the file was
# lost while the listener lived (the entrypoint's rm after a guardian that cron started early, or two guardians at once),
# want_off could not kill it and want_on could not bind a new one: an UNFIT node still "asked", and an unfit holder then
# released iscsid to it (nobody held iscsid).  The pid file is rewritten from the live listener (kept for people/sheets).
wanting() {
	wp=`pgrep -f "$WANTNAME\$" 2>/dev/null | head -1`
	[ -n "$wp" ] || return 1
	[ "`cat $WANTPID 2>/dev/null`" = "$wp" ] || echo $wp > $WANTPID
	return 0
}
want_on() {
	wanting && return 0
	( setsid $NSE python3 -c 'import socket,sys,time
s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
s.bind("\0"+sys.argv[1]); s.listen(1)
while True: time.sleep(3600)' "$WANTNAME" </dev/null >/dev/null 2>&1 & echo $! > $WANTPID )
}
want_off() { pkill -f "$WANTNAME\$" 2>/dev/null; rm -f $WANTPID; }   # r10e D7: every listener of this node, by name
etimes() { ps -o etimes= -p $1 2>/dev/null | tr -d ' '; }

state() {   # prints "<fit|booting|unfit> <reason>"
	if [ -f /root/dockersetup.failed ]; then
		echo "unfit docker_setup failed: `head -c 200 /root/dockersetup.failed`"; return
	fi
	# r10d (validator 10c G1): fit = an etcd container runs AND the node's loopers live.  With etcd alone a holder whose
	# stack stopped after etcd (loopers gone; a docker_setup stuck in the join loop counts below) kept iscsid for ever,
	# and its iscsirefresh.sh is the only one that logs in.  Loopers: heartbeatlooper.sh (started once, loops for ever),
	# heartbeat.py, zfsping.py (refreshdisown.sh restarts it, so any one of them counts; UNFITMIN covers short gaps).
	etcdup=0; timeout 10 docker ps -q -f name=^etcd$ 2>/dev/null | grep -q . && etcdup=1
	loopers=0; pgrep -f "$LOOPERS" >/dev/null 2>&1 && loopers=1
	if [ $etcdup -eq 1 ] && [ $loopers -eq 1 ]; then
		echo "fit etcd and loopers run"; return
	fi
	up=`etimes 1`
	if [ -n "$up" ] && [ "$up" -lt "$GRACE" ]; then
		echo "booting container up ${up}s"; return
	fi
	if pgrep -f docker-preload.sh >/dev/null 2>&1; then
		echo "booting image preload runs"; return
	fi
	[ $etcdup -eq 1 ] && what="no loopers" || what="no etcd"
	sp=`pgrep -f 'docker_setup[.a-z]*\.sh' | head -1`
	if [ -n "$sp" ]; then
		st=`etimes $sp`
		if [ -z "$st" ] || [ "$st" -lt "$SETUPMAX" ]; then
			echo "booting docker_setup runs (${st:-?}s), $what yet"; return
		fi
		[ $etcdup -eq 1 ] && echo "unfit docker_setup runs for ${st}s, etcd but no loopers" || echo "unfit docker_setup runs for ${st}s without an etcd"
		return
	fi
	[ $etcdup -eq 1 ] && { echo "unfit etcd runs but no heartbeat/zfsping looper and no docker_setup"; return; }
	echo "unfit no etcd and no docker_setup"
}

tick() {
	st=`state`; kind=${st%% *}
	now=`date +%s`
	if [ "$kind" = unfit ]; then
		[ -f $UNFITF ] || echo $now > $UNFITF
		unfitfor=$(( now - `cat $UNFITF 2>/dev/null || echo $now` ))
	else
		rm -f $UNFITF; unfitfor=0
	fi
	if mine && ! sockettaken; then
		# the old guardian's case: an iscsid parent left alive without its abstract socket (iscsid 6.2.1.11 crash)
		say "iscsid alive but its abstract socket is missing: killing it"
		pkill -9 -x iscsid 2>/dev/null; sleep 1; rm -f /var/run/iscsid.pid
	fi
	if mine; then
		want_off
		other=`otherwants`
		if [ "$kind" = unfit ] && [ -n "$other" ] && [ $unfitfor -ge $UNFITMIN ]; then
			say "releasing iscsid: this node is $st and ${other#@TOPSTOR_ISCSID_WANT_} wants it"
			pkill -TERM -x iscsid 2>/dev/null
			for i in 1 2 3 4 5; do mine || break; sleep 1; done
			mine && pkill -9 -x iscsid 2>/dev/null
			rm -f /var/run/iscsid.pid
		else
			say "holding iscsid ($st)"
		fi
		return 0
	fi
	if sockettaken; then
		if [ "$kind" = unfit ]; then
			want_off; say "not asking for iscsid (held by another container): this node is $st"
		else
			want_on; say "iscsid is held by another container; asking for it ($st)"
		fi
		return 0
	fi
	if [ "$kind" = unfit ]; then
		want_off; say "not starting iscsid: this node is $st"
		return 0
	fi
	say "starting iscsid ($st)"
	/usr/local/sbin/start-iscsid.sh >> $LOG 2>&1 && want_off
	return 0
}

case "$1" in
	tick) tick ;;
	state) state ;;
	*) echo "usage: $0 tick|state"; exit 1 ;;
esac
