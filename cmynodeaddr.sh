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
case $mode in
add)
 echo "$addr" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || { say "cmynodeaddr: no address ($addr)"; exit 1; }
 exec 9>>/TopStordata/cmynode.lock
 flock -w 120 9 || say "cmynodeaddr: ${addr}/$prefix no lock after 120 s, going on"
 try=1
 while [ $try -le 3 ]; do
  nmcli conn mod cmynode -ipv4.addresses ${addr}/$prefix 2>/dev/null
  nmcli conn mod cmynode +ipv4.addresses ${addr}/$prefix
  nmcli conn up cmynode >/dev/null 2>&1
  if nmcli -g ipv4.addresses conn show cmynode 2>/dev/null | tr ',' '\n' | tr -d ' ' | grep -qx "${addr}/$prefix" \
     && ip -o -4 addr show 2>/dev/null | awk '{print $4}' | grep -qx "${addr}/$prefix"; then
   say "cmynodeaddr: ${addr}/$prefix is on cmynode (try $try)"
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
