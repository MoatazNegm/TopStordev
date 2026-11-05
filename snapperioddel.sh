#!/bin/sh
# snapperioddel.sh <leader ip> <pool> <volume>: drop the snapshot schedule records of ONE deleted volume from the cluster
# (cifsremove.sh, nfsremove.sh: CIFS, home and NFS deletes, a user delete through VolumeDeleteHOME).
# QSD5.352 r8 (validator r7 N1): SnapShotPeriodDelete, which the Volume*Delete scripts run after the share is removed,
# deletes the records and sends the Snapperiod sync only while this node's crontab still has a line with the volume.
# crondelete (cifsremove.sh / nfsremove.sh) removes exactly those lines first, so the test always failed: the records
# Snapperiod/<period>/<pool>/<volume>/<stamp>/<receiver> stayed, the other nodes were never told (their lines stayed for
# good) and every later Snapperiod sync (pace/etctocron.py rebuilds the table from ALL records) put the deleted volume's
# 'Snapshotnowhost::<pool>/<volume>::' lines back, on this node too.  As DGdestroyPool does for a pool: the records go
# here, BEFORE crondelete, with a Snapperiod sync so every other node runs etctocron without them; this node is marked
# done (crondelete filters its table next, under the etctocron lock).  The filter '/<pool>/<volume>/' matches the key
# only (the value carries '%<pool>/<volume>%'), so vol_123 and xvol_12 keep their records when vol_12 goes.  The
# 'call/<id>' keys the schedules left (putcron.sh, value '/TopStor/Snapshotnowhost::<pool>/<volume>::...') go too.
export ETCDCTL_API=3
leaderip=`echo $@ | awk '{print $1}'`
pool=`echo $@ | awk '{print $2}'`
vol=`echo $@ | awk '{print $3}'`
[ -n "$leaderip" ] && [ -n "$pool" ] && [ -n "$vol" ] || exit 0
if /pace/etcdget.py $leaderip Snapperiod --prefix 2>/dev/null | grep -qF "/$pool/$vol/"; then
 /pace/etcddel.py $leaderip Snapperiod "/$pool/$vol/"
 me=`docker exec etcdclient /TopStor/etcdgetlocal.py clusternode 2>/dev/null`
 [ -n "$me" ] || me=`hostname -s`
 stamp=`date +%s`
 /pace/etcdput.py $leaderip sync/Snapperiod/Del_${vol}/request/$me Snapperiod_$stamp
 /pace/etcdput.py $leaderip sync/Snapperiod/Del_${vol}/request Snapperiod_$stamp
 echo "snapshot schedule records of $pool/$vol deleted, Snapperiod sync sent" >> /root/snapperioddel
fi
if /pace/etcdget.py $leaderip call --prefix 2>/dev/null | grep -qF "::$pool/$vol::"; then
 /pace/etcddel.py $leaderip call "::$pool/$vol::"
fi
exit 0
