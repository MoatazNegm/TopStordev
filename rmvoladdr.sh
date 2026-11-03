#!/bin/sh
# QSD5.351: take a volume address off this node when no other local volume still uses it.
#   rmvoladdr.sh <ip> [<prefix>] [<dataset to ignore>]
# Removes every cmynode entry <ip>/<any prefix> (an address stored with another prefix than the one in ip:subnet
# stayed behind before), re-applies cmynode, and in the container flavour also deletes the address from the live
# interface (as cifsremove.sh does since QSD5.337).  The address is KEPT when another filesystem/volume of this node
# (other than <dataset to ignore>, the volume being deleted or changed) still has it in ip:addr: CIFS shares of the
# same context share one address.  Used by VolumeChangeNFS (old address after a change), nfsremove.sh (delete) and
# VolumeDockerChange.py (CIFS change).
ip=$1
prefix=$2
skip=$3
echo "$ip" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || { echo "rmvoladdr: no address ($ip)"; exit 0; }
users=`/sbin/zfs get -H -o name,value -t filesystem,volume ip:addr 2>/dev/null | awk -v ip="$ip" -v skip="$skip" '$2==ip && $1!=skip {print $1}'`
if [ -n "$users" ]; then
 echo "rmvoladdr: keep $ip, still used by" $users
 exit 0
fi
changed=0
[ -n "$prefix" ] && nmcli conn mod cmynode -ipv4.addresses ${ip}/$prefix 2>/dev/null && changed=1
for a in `nmcli -g ipv4.addresses conn show cmynode 2>/dev/null | tr ',' ' '`; do
 case $a in
  $ip/*) nmcli conn mod cmynode -ipv4.addresses $a && changed=1 ;;
 esac
done
[ $changed -eq 1 ] && nmcli conn up cmynode
[ -f /TopStor/flavor.sh ] && . /TopStor/flavor.sh
if is_container 2>/dev/null; then
 for a in `ip -o -4 addr show | awk -v ip=$ip '{split($4,a,"/"); if (a[1]==ip) print $2"|"$4}'`; do
  ip addr del ${a#*|} dev ${a%|*}
 done
fi
echo "rmvoladdr: removed $ip"
