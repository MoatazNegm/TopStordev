#!/bin/sh
# cmynodeaddr.sh add <ip> <prefix>
# QSD5.352 (QC 698): put a volume address on the cmynode connection and make sure it is really there.
# 'nmcli conn mod' reads the whole connection, changes it and writes it back.  After a take-over VolumeCheck starts the
# NFS, CIFS, home and iSCSI volumes in parallel, so iscsi.sh, cifs.sh and nfs.sh changed cmynode at the same time and one
# write could drop the address another one had just added: the LUN address 10.11.11.163 stayed off the new owner for
# ~10 minutes (the portal existed, clients got 'No route to host') until a later sync ran iscsi.sh again.
# The volume address changes of cmynode run under the lock /TopStordata/cmynode.lock (also rmvoladdr.sh, cifsremove.sh,
# nfsnew.sh, cifs.sh DNS, VolumeChangeISCSI, VolumeDeleteISCSI, docker_primary.sh, bybyleader.sh, iscsiwatchdog.sh), and
# the address is checked on the connection and on the interface after 'conn up'; it is written again up to three times.
# Not under the lock (node setup / DNS paths that do not run beside volume starts): docker_setup*.sh, getdiscovery.sh,
# HostManualconfigDNS, VolumeDeleteNFS_non_container.
# QSD5.352 r2 (validator R2): the callers drop stdout (iscsi.py reads a PIPE), so every result line is also appended to
# /TopStordata/cmynodeaddr.log with the time, the caller and the try number (kept below ~1 MB: one old copy .1).
mode=$1
LOG=${CMYNODEADDR_LOG:-/TopStordata/cmynodeaddr.log}
# only the caller's program name and pid: its arguments may hold a CHAP secret (iscsi.sh)
caller=`ps -o args= -p $PPID 2>/dev/null | awk '{n=$1; if (n ~ /(^|\/)(ba|da)?sh$/ && NF>1) n=$2; print n}'`:$PPID
say() {
 echo "$1"
 echo "`date '+%F %T'` [$caller] $1" >> $LOG 2>/dev/null
}
if [ -f $LOG ] && [ `stat -c %s $LOG 2>/dev/null || echo 0` -gt 1048576 ]; then mv -f $LOG $LOG.1 2>/dev/null; fi
addr=$2
prefix=${3:-24}
# QSD5.352 r10 (QC 680): a volume address that moved here (take-over, return, address change) was not announced: a
# client that had talked to the old node kept the address on the old MAC until its ARP entry aged (SMB IO_TIMEOUT for
# minutes).  As docker_primary.sh does for the cluster address: a gratuitous ARP on every interface with a connected
# route to the address, a few times, in the background, without the cmynode lock (fd 9 closed).
announce() {
 for dev in `ip -o -4 route show to match $addr 2>/dev/null | grep -v '^default' | sed -n 's/.* dev \([^ ]*\).*/\1/p' | sort -u`
 do
  arping -U -c 1 -I $dev -s $addr $addr >/dev/null 2>&1
 done
}
case $mode in
add)
 echo "$addr" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || { say "cmynodeaddr: no address ($addr)"; exit 1; }
 exec 9>>/TopStordata/cmynode.lock
 flock -w 120 9 || say "cmynodeaddr: ${addr}/$prefix no lock after 120 s, going on"
 try=1
 while [ $try -le 3 ]; do
  nmcli conn mod cmynode -ipv4.addresses ${addr}/$prefix 2>/dev/null
  nmcli conn mod cmynode +ipv4.addresses ${addr}/$prefix
  # r10o (O3): tries 1 and 2 apply it in place (cmynodeapply.sh: no bond0 re-activation that takes the cluster ip away
  # for seconds); the last try re-activates as before
  if [ $try -lt 3 ] && [ -x /TopStor/cmynodeapply.sh ]; then /TopStor/cmynodeapply.sh cmynodeaddr.sh >/dev/null 2>&1; else nmcli conn up cmynode >/dev/null 2>&1; fi
  if nmcli -g ipv4.addresses conn show cmynode 2>/dev/null | tr ',' '\n' | tr -d ' ' | grep -qx "${addr}/$prefix" \
     && ip -o -4 addr show 2>/dev/null | awk '{print $4}' | grep -qx "${addr}/$prefix"; then
   say "cmynodeaddr: ${addr}/$prefix is on cmynode (try $try)"
   ( announce; sleep 1; announce; sleep 2; announce ) 9>&- >/dev/null 2>&1 </dev/null &
   exit 0
  fi
  say "cmynodeaddr: ${addr}/$prefix missing after try $try"
  try=$((try+1))
  sleep 2
 done
 say "cmynodeaddr: ${addr}/$prefix FAILED after 3 tries"
 exit 1 ;;
*)
 echo "usage: cmynodeaddr.sh add <ip> <prefix>"
 exit 1 ;;
esac
