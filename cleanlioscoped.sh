#!/bin/bash
# cleanlioscoped.sh [-n] -- CONTAINER flavour only.  Replaces "targetcli clearconfig" in the node scripts.
#
# All node containers (of every cluster on this host: zfs1, zfs2, pzfs ...) share ONE kernel, and the disk exports of
# LIO (targets, backstores) live in that kernel, not in the container.  "targetcli clearconfig" therefore wipes the exports
# of EVERY node, also of nodes that are running and have pools on those disks: their disks vanish, the pools suspend, and a
# suspended pool makes every `sync` on the host hang (2026-10-07: a restart of pzfs hung that way).
#
# This removes only what belongs to this node or to a node that is gone:
#   - an iSCSI target iqn.2016-03.com.<host>:t1 is THIS node's when <host> is this node's name or one of its portal ips is
#     an ip of this node; it is GONE when none of its portal ips answers a ping.  Both are deleted.  A target whose portal
#     answers belongs to a running node (any cluster) and is left alone.
#   - a block backstore <device>-<host> is deleted when its <host> has no surviving target (own and dead nodes' disks),
#     and kept when it belongs to a surviving target.
# Safety: when this node cannot reach its own default gateway the network is not up yet, "no answer" means nothing, and then
# only this node's own objects are removed.
# -n: dry run, only prints what would be deleted.   Log: /root/lioclean.log.
# Test hooks (environment): TARGETCLI, PING, LIO_IP (ip command), LIO_ME (own host name).
DRY=0; [ "$1" = "-n" ] && DRY=1
TC=${TARGETCLI:-targetcli}; PING=${PING:-ping}; IPC=${LIO_IP:-ip}
ME=${LIO_ME:-`hostname`}
log() { echo "`date '+%H:%M:%S'` cleanlioscoped: $*" >> /root/lioclean.log; [ "$DRY" = 1 ] && echo "$*"; }
del() { # del <what> <targetcli path> delete <name>
	log "delete $1"
	[ "$DRY" = 1 ] || timeout 60 $TC "$2" "$3" "$4" >/dev/null 2>&1
}
MYIPS=" `$IPC -4 -o addr show 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | tr '\n' ' '` "
GW=`$IPC route 2>/dev/null | awk '/^default/{print $3; exit}'`
NETOK=0; [ -n "$GW" ] && $PING -c1 -W1 $GW >/dev/null 2>&1 && NETOK=1
[ $NETOK = 0 ] && log "default gateway '$GW' does not answer: only this node's own objects are removed"

ALIVE=" "
TREE=`timeout 30 $TC ls /iscsi 2>/dev/null`
for iqn in `echo "$TREE" | sed -n 's/.*o- \(iqn\.2016-03\.com\.[A-Za-z0-9._-]*:t1\) .*/\1/p'`; do
	host=${iqn#iqn.2016-03.com.}; host=${host%:t1}
	own=0; live=0
	[ "$host" = "$ME" ] && own=1
	for ip in `timeout 20 $TC ls /iscsi/$iqn/tpg1/portals 2>/dev/null | sed -n 's/.*o- \([0-9.]*\):[0-9]* .*/\1/p'`; do
		case "$MYIPS" in *" $ip "*) own=1 ;; esac
		if [ $own = 0 ] && [ $live = 0 ]; then
			$PING -c1 -W1 $ip >/dev/null 2>&1 || $PING -c1 -W1 $ip >/dev/null 2>&1 && live=1
		fi
	done
	if [ $own = 1 ]; then
		del "target $iqn (this node's)" /iscsi delete "$iqn"
	elif [ $live = 0 ] && [ $NETOK = 1 ]; then
		del "target $iqn (no portal answers: the node is gone)" /iscsi delete "$iqn"
	else
		ALIVE="$ALIVE$host "
		log "keep target $iqn (a running node)"
	fi
done
for bs in `timeout 30 $TC ls /backstores/block 2>/dev/null | sed -n 's/.*o- \([A-Za-z0-9._]*-[A-Za-z0-9._-]*\) \.\.\..*/\1/p'`; do
	host=${bs#*-}
	case "$ALIVE" in *" $host "*) log "keep backstore $bs (its node is running)"; continue ;; esac
	[ $NETOK = 0 ] && [ "$host" != "$ME" ] && { log "keep backstore $bs (network not verified)"; continue; }
	del "backstore $bs" /backstores/block delete "$bs"
done
[ "$DRY" = 1 ] || timeout 60 $TC saveconfig >/dev/null 2>&1
exit 0
