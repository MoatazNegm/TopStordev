#!/bin/sh
# QSD5.352 r10o (QC proof 10n O3): apply a changed cmynode profile (addresses, DNS) to the running device.
# 'nmcli conn up cmynode' RE-ACTIVATES bond0: every address on it -- the cluster ip of the leader too -- is gone for
# seconds.  Under load a share start on the leader (cmynodeaddr.sh, then cifs.sh for the DNS) did it twice back to back;
# the follower's heartbeat saw the leader down at 10.11.11.200, took the leadership from the live leader and both nodes
# led with their own etcd (r10n s2, 16:14 UTC: isinsync=no for good).  Container flavour: 'nmcli device reapply <dev>'
# changes the device in place; when that fails (or in the physical flavour, unchanged) 'nmcli conn up cmynode' as before.
# usage: cmynodeapply.sh <caller>   (rc of the nmcli that applied it; one line per call in /root/cmynodeapply.log)
[ -f /TopStor/flavor.sh ] && . /TopStor/flavor.sh
log() { echo "`date '+%F %T'` ${1:-?}: $2" >> /root/cmynodeapply.log 2>/dev/null; }
if type is_container >/dev/null 2>&1 && is_container; then
 dev=`nmcli -g GENERAL.DEVICES conn show cmynode 2>/dev/null | cut -d, -f1`
 if [ -n "$dev" ] && nmcli device reapply "$dev" >/dev/null 2>&1; then
  log "$1" "cmynode applied in place (device reapply $dev)"
  exit 0
 fi
 log "$1" "device reapply ${dev:-<no device>} failed: conn up cmynode"
fi
nmcli conn up cmynode
