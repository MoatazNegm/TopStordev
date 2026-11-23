#!/bin/bash
# shareaddr.sh add|del <ip> [<bits>]
# QSD5.337 (test 646 QX-047 step 3): the one place where a share/volume address (NFS, CIFS, HOME, iSCSI, the temporary .254)
# is put on or taken off the node. It used to be "nmcli conn mod cmynode +/-ipv4.addresses ...; nmcli conn up cmynode" in every
# script. cmynode is the only profile on bond0 and carries the node address, the cluster address and every share address: each
# "conn up" is a new activation that tears bond0 down (all addresses gone 1-2 s). One NFS address change ran it 5 times in 6 s on
# the leader, the follower lost the cluster address and took over (split brain, the pool imported on both nodes).
# Now the address is changed live with ip(8) only (no re-activation, the other addresses are not touched) and the profile is only
# edited (nmcli conn mod, never conn up/reload), so the address is still there after a reboot or a later re-activation.
#   add: ip addr add <ip>/<bits> dev <dev> unless the address is already on the device, then a gratuitous ARP (arping -U) so
#        the neighbours learn the address at once; the profile gets <ip>/<bits> (other prefixes of the same ip are dropped).
#   del: ip addr del of every prefix of <ip> on the device (nothing if absent); the profile loses every <ip>/* entry.
#        The node's own address (first address of cmynode) is never removed.
op=$1
ip=$2
bits=$3
log=/root/shareaddrlog
echo "$ip" | grep -Eq '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' || { echo "shareaddr.sh: bad address '$ip'" >&2; exit 2; }
echo "$bits" | grep -Eq '^[0-9]{1,2}$' || bits=''
conn=cmynode
dev=`nmcli -g GENERAL.DEVICES conn show $conn 2>/dev/null | cut -d, -f1`
[ -z "$dev" ] && dev=bond0
# nmcli conn mod is a read-modify-write of the profile: parallel edits (several share scripts) must not lose each other's change
# merge M+A: the same lock as M's cmynodeaddr.sh / rmvoladdr.sh (/TopStordata/cmynode.lock, QSD5.352 QC 698), so the
# scripts of both lines never edit cmynode at the same time (A had its own /tmp/shareaddr.nmcli.lock)
exec 7>>/TopStordata/cmynode.lock
flock -w 120 7
profaddrs=`nmcli -g ipv4.addresses conn show $conn 2>/dev/null | tr ',' '\n' | tr -d ' '`
profip=`echo "$profaddrs" | awk -F/ -v ip="$ip" '$1==ip'`
devip=`ip -o -4 addr show dev $dev 2>/dev/null | awk '{print $4}' | awk -F/ -v ip="$ip" '$1==ip'`
case $op in
 add)
  [ -z "$bits" ] && bits=`echo "$profip" | head -n 1 | cut -d/ -f2`
  [ -z "$bits" ] && bits=24
  added=0
  if [ -z "$devip" ];
  then
   ip addr add $ip/$bits dev $dev && added=1
  fi
  if [ $added -eq 1 ] && command -v arping >/dev/null 2>&1;
  then
   timeout 5 arping -U -c 2 -I $dev $ip >/dev/null 2>&1
  fi
  for a in $profip;
  do
   [ "$a" = "$ip/$bits" ] || nmcli conn mod $conn -ipv4.addresses $a
  done
  echo "$profip" | grep -qxF "$ip/$bits" || nmcli conn mod $conn +ipv4.addresses $ip/$bits
  echo `date +%T` add $ip/$bits dev $dev live=$added "(was: ${devip:-none})" profile="(was: `echo $profip`)" by $PPID `ps -o args= -p $PPID 2>/dev/null | cut -c1-80` >> $log
  ;;
 del)
  nodeaddr=`echo "$profaddrs" | head -n 1 | cut -d/ -f1`
  if [ "$ip" = "$nodeaddr" ];
  then
   echo `date +%T` del $ip refused: the node address of $conn >> $log
   exit 3
  fi
  for a in $devip;
  do
   ip addr del $a dev $dev
  done
  for a in $profip;
  do
   nmcli conn mod $conn -ipv4.addresses $a
  done
  echo `date +%T` del $ip dev $dev "live=(${devip:-none})" "profile=(`echo $profip`)" by $PPID `ps -o args= -p $PPID 2>/dev/null | cut -c1-80` >> $log
  ;;
 *)
  echo "usage: shareaddr.sh add|del <ip> [<bits>]" >&2
  exit 2
  ;;
esac
exit 0
