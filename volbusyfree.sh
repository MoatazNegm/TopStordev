#!/bin/sh
# volbusyfree.sh <leader> <leader ip> <this host> <this host ip> <pool> <volume>
# QSD5.352 r9 (prover D6, D5): 'zfs destroy' of a CIFS share or a home failed with NFS1001 (dataset busy) when a share
# container of THIS node still had the dataset mounted: two homes on one address deleted 1 s apart (the container that
# served both was started again for the other home between the first delete and the second destroy), or an old-address
# HOMEE-<ip> started again after an address change.  Run by VolumeDeleteHOME / VolumeDeleteCIFS between destroy tries:
# every HOMEE-<ip> / CIFS-<ip> container of this node that mounts /<pool>/<volume> is removed (VolumeDockerChange.py: the
# container, and the address unless another dataset still has it), and when another ACTIVE share of this node is still on
# that address it is started again through cifs.py with the records of the LEADER (the deleted volume's record is gone,
# so the new container does not mount it), in the background.  Domain shares (CIFS_<domain>-<ip>) are not touched.
leader=$1; leaderip=$2; myhost=$3; myhostip=$4; pool=$5; vol=$6
[ -n "$pool" ] && [ -n "$vol" ] || exit 0
for c in `docker ps --format '{{.Names}}' 2>/dev/null`; do
 case $c in
  HOMEE-*) vt=HOMEE; kind=home ;;
  CIFS-*) vt=CIFS; kind=cifs ;;
  *) continue ;;
 esac
 docker inspect -f '{{range .Mounts}}{{.Source}} {{end}}' $c 2>/dev/null | tr ' ' '\n' | grep -qFx "/$pool/$vol" || continue
 ip=${c#*-}
 echo "`date +%T` $c holds $pool/$vol: removed" >> /root/volbusyfree
 /TopStor/VolumeDockerChange.py $ip 24 $vt $pool/$vol
 other=`/TopStor/getvols.sh $kind | grep -vF "$pool/$vol/" | grep -F "/$ip/" | grep '/active$' | head -n 1`
 if [ -n "$other" ]; then
  opool=`echo $other | cut -d/ -f1`; oname=`echo $other | cut -d/ -f2`; osub=`echo $other | cut -d/ -f9`
  echo "`date +%T` $opool/$oname still on $ip: share started again" >> /root/volbusyfree
  ( /TopStor/cifs.py $leader $leaderip $myhost $myhostip $leaderip $opool $oname $ip ${osub:-24} $vt > /dev/null 2>&1 & )
 fi
done
exit 0
