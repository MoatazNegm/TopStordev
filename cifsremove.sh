#!/bin/sh
cd /TopStor
export ETCDCTL_API=3
enpdev='enp0s8'
leaderip=`echo $@ | awk '{print $1}'`
pool=`echo $@ | awk '{print $2}'`
vol=`echo $@ | awk '{print $3}'`
volip=`echo $@ | awk '{print $4}'`
vtype=`echo $@ | awk '{print $5}'`
echo $@ > /root/`basename "$0"`

docker exec etcdclient /TopStor/logqueue.py `basename "$0"` running $userreq
/TopStor/etcddel.py $leaderip vol $vol
/TopStor/etcddel.py $leaderip replivol $vol
/TopStor/etcddel.py $leaderip size $vol 
#/TopStor/deltolocal.py size $vol 
#/TopStor/deltolocal.py vol $vol 
# QSD5.352 r8 (validator r7 N1): the volume's schedule records first (and a Snapperiod sync), then this node's lines
/TopStor/snapperioddel.sh $leaderip $pool $vol
/TopStor/crondelete $vol $pool    # r9 (validator r8 R2): pool-anchored
rm -rf /TopStordata/smb.${volip}.new
echo vol = $vol
/TopStor/delblock.py start${vol}_only stop${vol}_only /TopStordata/smb.$volip  ;
rm -rf /TopStordata/smb.$vol
rm -rf /$pool/smb.$vol
rm -rf /TopStordata/tempsmb.$volip
rm -rf /TopStordata/smb.$volip
cat /TopStordata/smb.${volip}.new
cat /TopStordata/smb.${volip}.new > /TopStordata/smb.${volip}
resname=$vtype'-'$volip
# r9: the container of exactly this address (a plain 'grep <ip>' took HOMEE-10.11.11.169 for 10.11.11.16)
resname=`docker ps --format '{{.Names}}' | awk -v s="-$volip" 'length($0) > length(s) && substr($0, length($0)-length(s)+1) == s'`
[ -n "$resname" ] && docker  rm -f $resname 
cat /TopStordata/smb.$volip | grep start | grep only
if [ $? -ne 0 ]
then 
  exec 9>>/TopStordata/cmynode.lock; flock -w 120 9   # QSD5.352: cmynode changes one at a time (cmynodeaddr.sh)
  nmcli conn mod cmynode -ipv4.addresses $volip 
  # QSD5.337 (container flavour): the address is stored as <ip>/<prefix>, so the removal above did not match and the home
  # address stayed on cmynode/bond0 (answering ping for minutes): remove it with its prefix, then from the live interface
  [ -f /TopStor/flavor.sh ] && . /TopStor/flavor.sh
  if is_container 2>/dev/null && [ -n "$volip" ]; then
   for a in `nmcli -g ipv4.addresses conn show cmynode | tr ',' ' '`; do
    case $a in
     $volip/*) nmcli conn mod cmynode -ipv4.addresses $a ;;
    esac
   done
   for a in `ip -o -4 addr show | awk -v ip=$volip '{split($4,a,"/"); if (a[1]==ip) print $2"|"$4}'`; do
    ip addr del ${a#*|} dev ${a%|*}
   done
  fi
  nmcli conn up cmynode
  flock -u 9
  rm -rf /TopStordata/smb.$volip;
else
 # QSD5.352 r9 (prover D6): another share is still on the address.  This branch started the container again with
 # 'docker run' of an image that is not there (10.11.11.124:5000/smb) and without the address ($ipaddr was never set), so
 # the remaining share stayed down until a VolumeCheck pass started it, and that start raced the next delete: two homes on
 # one address deleted 1 s apart, the second 'zfs destroy' found the dataset held by the new container (NFS1001).  The
 # share is started again through cifs.py now (per-address lock, records from the LEADER: this volume's record is already
 # gone, so the new container does not mount it), in the background; a domain share (CIFS_<domain>) is left to VolumeCheck.
 case $vtype in
  HOMEE|HOME) kind=home; ctype=HOMEE ;;
  CIFS) kind=cifs; ctype=CIFS ;;
  *) kind='' ;;
 esac
 other=''
 [ -n "$kind" ] && other=`/TopStor/getvols.sh $kind | grep -vF "$pool/$vol/" | grep -F "/$volip/" | grep '/active$' | head -n 1`
 if [ -n "$other" ]; then
  opool=`echo $other | cut -d/ -f1`; oname=`echo $other | cut -d/ -f2`; osub=`echo $other | cut -d/ -f9`
  leader=`docker exec etcdclient /TopStor/etcdgetlocal.py leader`
  myhost=`docker exec etcdclient /TopStor/etcdgetlocal.py clusternode`
  myhostip=`docker exec etcdclient /TopStor/etcdgetlocal.py clusternodeip`
  echo "`date +%T` $opool/$oname still on $volip: share started again" >> /root/cifsremove.restart
  ( /TopStor/cifs.py $leader $leaderip $myhost $myhostip $leaderip $opool $oname $volip ${osub:-24} $ctype > /dev/null 2>&1 & )
 fi
fi
/TopStor/etcddel.py $leaderip vol $vol
/TopStor/etcddel.py $leaderip replivol $vol
# QSD5.337: nothing of the address' share is left behind (delblock.py rewrites .new; the lock came from cifs.sh)
if [ -n "$volip" ] && [ ! -s /TopStordata/smb.$volip ]; then
 rm -f /TopStordata/smb.${volip}.new /TopStordata/cifs.${volip}.lock /TopStordata/smb.$volip
fi
 docker exec etcdclient /TopStor/logqueue.py `basename "$0"` finish $userreq
