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
# the volume list of VolumeCheck (getvols.sh) comes from /<pool>/smb.<volume>: it goes first, so a VolumeCheck pass that runs
# while this script works does not take the volume (no longer in etcd) as dirty and re-create the address container
rm -rf /$pool/smb.$vol
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
# test 643 step 3: the address container serves every share of the address. It was removed here before the script knew whether
# other shares remain (all of them went down), the re-run used an empty address and an image that is not installed, and
# VolumeCheck then re-created the container once per remaining share (outages of 12-18 s and more).  Now:
# - the share's block is cut out of /TopStordata/smb.<address> in place (truncate and write, same inode): the file is
#   bind-mounted into the running container as /config/smb.conf, the file smbd reads (supervisord: --configfile);
# - other shares left: smbd and nmbd reload the config, the removed share is closed and its dataset is unmounted in the
#   container (the dataset is destroyed next); the container keeps running, the other shares stay reachable;
# - no share left: the container and the address go, as before.
# Parallel deletes on one address are serialized (each one edits the same file).
log=/root/cifsremovelog
exec 9>/tmp/cifsremove.${volip}.lock
flock -w 120 9
rm -rf /TopStordata/smb.${volip}.new
/TopStor/delblock.py start${vol}_only stop${vol}_only /TopStordata/smb.$volip  ;
rm -rf /TopStordata/smb.$vol
rm -rf /TopStordata/tempsmb.$volip
touch /TopStordata/smb.${volip}.new
cat /TopStordata/smb.${volip}.new > /TopStordata/smb.${volip}
rm -rf /TopStordata/smb.${volip}.new
cat /TopStordata/smb.${volip}
# the container of this address only (a name ending in -<address>: 10.11.11.15 must not find CIFS-10.11.11.156)
resname=`docker ps --format '{{.Names}}' | awk -v ip="-$volip" 'length($0) > length(ip) && substr($0, length($0)-length(ip)+1) == ip' | head -n 1`
echo `date +%T` $vol $volip container=$resname >> $log
grep start /TopStordata/smb.$volip | grep -q only
if [ $? -ne 0 ]
then 
  [ -n "$resname" ] && docker rm -f $resname
  # merge M+A: the address goes through M's rmvoladdr.sh (every <ip>/<prefix> entry, the live interface, kept while another
  # volume of this node still uses it: QC 615, QSD5.351) instead of A's unconditional 'shareaddr.sh del'
  [ -n "$volip" ] && [ -x /TopStor/rmvoladdr.sh ] && /TopStor/rmvoladdr.sh $volip "" "$pool/$vol"
  rm -rf /TopStordata/smb.$volip;
  echo `date +%T` last share of $volip: container and address removed >> $log
else
  reloaded=0
  # the local-user share image (cifs.sh, moataznegm/quickstor:smb) runs smbd on /config/smb.conf; a domain member container
  # builds its own config at start and cannot reload it
  if [ -n "$resname" ] && docker exec $resname test -f /config/supervisord.conf
  then
    # a container started on an older copy of the file (another inode) gets the new content written into its own copy
    docker exec $resname cat /config/smb.conf | cmp -s - /TopStordata/smb.$volip
    if [ $? -ne 0 ]
    then
      docker exec -i $resname sh -c 'cat > /config/smb.conf' < /TopStordata/smb.$volip
      echo `date +%T` config copied into $resname >> $log
    fi
    try=0
    while [ $try -lt 10 ]
    do
      try=$((try+1))
      docker exec $resname smbcontrol all reload-config
      if [ $? -ne 0 ]
      then
        sleep 1
        continue
      fi
      reloaded=1
      docker exec $resname smbclient -L //127.0.0.1 -N -g 2>/dev/null | grep -q "^Disk|$vol|"
      if [ $? -ne 0 ]
      then
        break
      fi
      sleep 1
    done
    echo `date +%T` reload-config $resname reloaded=$reloaded tries=$try shares: `docker exec $resname smbclient -L //127.0.0.1 -N -g 2>/dev/null | grep '^Disk|' | cut -d'|' -f2` >> $log
    if [ $reloaded -eq 1 ]
    then
      docker exec $resname smbcontrol smbd close-share $vol
      docker exec $resname umount /$pool/$vol || docker exec $resname umount -l /$pool/$vol
    fi
  fi
  if [ $reloaded -eq 0 ]
  then
    # no container that can reload: VolumeCheck starts the address container once with the remaining shares (cifs.py)
    [ -n "$resname" ] && docker rm -f $resname
    echo `date +%T` no reload, $resname removed for VolumeCheck to re-create >> $log
  fi
fi
flock -u 9
exec 9>&-
/TopStor/etcddel.py $leaderip vol $vol
/TopStor/etcddel.py $leaderip replivol $vol
# QSD5.337: nothing of the address' share is left behind (delblock.py rewrites .new; the lock came from cifs.sh)
if [ -n "$volip" ] && [ ! -s /TopStordata/smb.$volip ]; then
 rm -f /TopStordata/smb.${volip}.new /TopStordata/cifs.${volip}.lock /TopStordata/smb.$volip
fi
 docker exec etcdclient /TopStor/logqueue.py `basename "$0"` finish $userreq
