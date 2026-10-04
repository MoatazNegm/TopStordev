#!/bin/sh
# iscsidowner.sh -- source it:  [ -f /TopStor/iscsidowner.sh ] && . /TopStor/iscsidowner.sh
#
# CONTAINER flavour only. Every zfs container uses the HOST network namespace for iSCSI, and that
# namespace has room for exactly one iscsid (one abstract socket). Whoever started it first (zfs or
# zfs2) owns it, the other node must not log sessions in/out, rescan or clean up: its iscsiadm would
# talk to the OTHER node's iscsid and could tear down that node's live sessions.
#   iscsid_foreign   true when this is the container flavour, this container runs no iscsid, and the
#                    socket is held by another container. Evaluated at every call: when the owner goes
#                    down, iscsi-guardian.sh here starts our own iscsid and this node takes over.
# Physical flavour / no host-ns bind mount: always false (nothing changes).
[ -f /TopStor/flavor.sh ] && . /TopStor/flavor.sh
iscsid_foreign() {
	is_container 2>/dev/null || return 1
	[ -e /host-ns/net ] || return 1
	pgrep -x iscsid >/dev/null && return 1
	nsenter --net=/host-ns/net grep -q ISCSIADM_ABSTRACT_NAMESPACE /proc/net/unix 2>/dev/null
}
