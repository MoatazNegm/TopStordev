#!/usr/bin/bash
# cleanlioluns.sh - remove every trace of LIO-exported disks from the zfs container.
#
# `targetcli clearconfig` only clears the TARGET side. The LUNs that were
# attached earlier through iscsiadm stay in the kernel (as /dev/sdX with
# vendor LIO-ORG) together with the iSCSI sessions, node records and
# discovery records that created them, and /dev is a tmpfs so the stale
# /dev/sdX nodes never go away by themselves.
#
# This script (idempotent, safe to run repeatedly):
#   1. ends every iSCSI session, including stale ones (target gone, TRANSPORT
#      WAIT / FREE / REOPEN) that a plain logout cannot remove
#   2. deletes all iscsiadm node + discovery records
#   3. force-deletes any remaining SCSI device whose vendor is LIO-ORG
#   4. removes the stale /dev/sdX nodes left behind
#   5. clears the target side (targetcli clearconfig)
#
# Loop devices (/dev/loopN) and their backing images are NOT touched.
# Usage: /TopStor/cleanlioluns.sh

LIOVENDOR='LIO-ORG'

# 1. end every iSCSI session - healthy, stale or orphaned.
#    A plain logout is tried first (30s timeout: a dead transport can block
#    it). Sessions whose target is gone (TRANSPORT WAIT / FREE / REOPEN)
#    cannot log out - "error 32 - target likely not connected" - and
#    sessions left by an earlier iscsid are unknown to the current one. For
#    those, iscsid is made to give up itself: a node record with
#    node.session.reopen_max=1 is written per session (sessions are found
#    in sysfs, so any IP works), iscsid is restarted once, re-adopts them,
#    fails one reopen and tears them down. Records are put back afterwards
#    (step 2 deletes them all anyway).
SYS=/sys/class/iscsi_session
CONN=/sys/class/iscsi_connection
WAIT=${CLEARSTALE_WAIT:-90}		# seconds to wait for iscsid to give up

rd()          { cat "$1" 2>/dev/null; }
sess_tgt()    { rd $SYS/session$1/targetname; }
sess_portal() { echo "$(rd $CONN/connection$1:0/persistent_address):$(rd $CONN/connection$1:0/persistent_port),$(rd $SYS/session$1/tpgt)"; }
sess_info()   { echo "$(sess_tgt $1) $(sess_portal $1) [$(rd $SYS/session$1/state)/$(rd $CONN/connection$1:0/state)]"; }
gone()        { [ ! -d $SYS/session$1 ]; }

end_sessions() {
	local sids sid left saved t p old i n rc=0 s
	sids=$(for s in $SYS/session*; do [ -d "$s" ] && echo ${s##*session}; done)
	[ -n "$sids" ] || { echo "no iSCSI sessions"; return 0; }
	for sid in $sids; do echo "session $sid: $(sess_info $sid)"; done

	pgrep -x iscsid >/dev/null || systemctl start iscsid >/dev/null 2>&1

	# plain logout
	for sid in $sids; do
		timeout 30 iscsiadm -m session -r $sid -u >/dev/null 2>&1
	done

	# whatever is left: make iscsid give up on it
	left=""
	for sid in $sids; do gone $sid || left="$left $sid"; done
	if [ -n "$left" ]; then
		echo "logout failed for:$left - making iscsid give up on them"
		saved=$(mktemp)		# "sid|target|portal|old reopen_max (or new)"
		for sid in $left; do
			t=$(sess_tgt $sid); p=$(sess_portal $sid)
			old=$(iscsiadm -m node -T "$t" -p "$p" 2>/dev/null | sed -n 's/^node.session.reopen_max = //p')
			if [ -z "$old" ]; then
				iscsiadm -m node -o new -T "$t" -p "$p" >/dev/null 2>&1
				old=new
			fi
			echo "$sid|$t|$p|$old" >> $saved
			iscsiadm -m node -T "$t" -p "$p" -o update -n node.session.reopen_max -v 1 >/dev/null 2>&1
		done

		# iscsid reads the record when it adopts the session, i.e. at start-up
		systemctl restart iscsid >/dev/null 2>&1

		for ((i = 0; i < WAIT; i += 3)); do
			n=0; for sid in $left; do gone $sid || n=1; done
			[ $n = 0 ] && break
			sleep 3
		done

		# put the records back as they were
		while IFS='|' read -r sid t p old; do
			# a session still there keeps its record (the only handle on it)
			gone $sid || [ "$old" != new ] || old=0
			if [ "$old" = new ]; then
				iscsiadm -m node -o delete -T "$t" -p "$p" >/dev/null 2>&1
			else
				iscsiadm -m node -T "$t" -p "$p" -o update -n node.session.reopen_max -v "$old" >/dev/null 2>&1
			fi
		done < $saved
		rm -f $saved
	fi

	for sid in $sids; do
		if gone $sid; then echo "ended: session $sid"
		else echo "NOT ended: session $sid: $(sess_info $sid)" >&2; rc=1; fi
	done
	return $rc
}
end_sessions

# 2. node records (targets we logged in to) and discovery records (sendtargets)
timeout 30 iscsiadm -m node -o delete 2>/dev/null
iscsiadm -m discoverydb 2>/dev/null | awk '{print $1}' | while IFS=: read -r ip port; do
	timeout 30 iscsiadm -m discoverydb -t sendtargets -p "$ip:$port" -o delete 2>/dev/null
done
rm -rf /var/lib/iscsi/nodes/* /var/lib/iscsi/send_targets/* 2>/dev/null

# 3. anything the logout did not free: delete the SCSI device via sysfs
for blk in /sys/block/sd*; do
	[ -e "$blk/device/vendor" ] || continue
	if [ "$(tr -d ' \n' < $blk/device/vendor)" = "$LIOVENDOR" ]; then
		echo "removing leftover LIO disk ${blk##*/}"
		echo 1 > $blk/device/delete
	fi
done

# 4. /dev is a tmpfs: drop nodes whose kernel device no longer exists
udevadm settle 2>/dev/null
for node in /dev/sd*; do
	[ -b "$node" ] || continue
	[ -e /sys/class/block/${node#/dev/} ] || rm -f "$node"
done
rm -f /dev/disk/by-id/scsi-sd* 2>/dev/null   # links made by caddtargetdisks.sh

# 5. target side
targetcli clearconfig confirm=True >/dev/null
targetcli saveconfig >/dev/null

echo "--- remaining iSCSI sessions:"
if iscsiadm -m session 2>/dev/null; then
	# Orphaned kernel sessions (created by an iscsid instance that no longer
	# exists) cannot be logged out by the current iscsid: iscsiadm answers
	# "session not found". They hold no disks once step 3 has run.
	echo "WARNING: iSCSI sessions above could not be logged out (orphaned in the kernel)" >&2
else
	echo none
fi
echo "--- remaining LIO disks:"; lsblk -n -o NAME,VENDOR | grep "$LIOVENDOR" || echo none
