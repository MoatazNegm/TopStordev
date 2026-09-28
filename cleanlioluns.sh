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
#   1. logs out of every iSCSI session
#   2. deletes all iscsiadm node + discovery records
#   3. force-deletes any remaining SCSI device whose vendor is LIO-ORG
#   4. removes the stale /dev/sdX nodes left behind
#   5. clears the target side (targetcli clearconfig)
#
# Loop devices (/dev/loopN) and their backing images are NOT touched.
# Usage: /TopStor/cleanlioluns.sh

LIOVENDOR='LIO-ORG'

# 1. log out of all sessions; the timeout is needed because sessions in
#    TRANSPORT WAIT / REOPEN (target already gone) can block a logout.
if iscsiadm -m session &>/dev/null; then
	timeout 30 iscsiadm -m session -u
	# anything still there: tear it down session by session
	for sid in $(iscsiadm -m session 2>/dev/null | sed -n 's/^[a-z]*: \[\([0-9]*\)\].*/\1/p'); do
		timeout 30 iscsiadm -m session -r $sid -u
	done
fi

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
