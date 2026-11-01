#!/bin/bash
cd /TopStor
rm -rf /TopStordata/*.zip
# QSD5.344: the config file never shows a secret (QC test 674): the partner pass phrase (last field of Partner/*, also an
# older clear one, and the phrase part of an old sync/Partnr request key) and the iSCSI CHAP secret (field 8 of
# volumes/ISCSI/*) are printed as ****
masksecrets() {
	sed -E -e "s#^(\('Partner/[^']*', '[^/']*/[^/']*/[^/']*/)[^']*'#\1****'#" \
		-e "s#(sync/Partnr/Add_[^']*::[0-9]+::)[^']*(/request[^']*')#\1****\2#" \
		-e "s#^(\('volumes/ISCSI/[^']*', '([^/']*/){7})[^/']*#\1****#"
}
leader=$(/usr/bin/docker exec etcdclient /TopStor/etcdgetlocal.py leader)
leaderip=`docker exec etcdclient /TopStor/etcdgetlocal.py leaderip`
myhost=`docker exec etcdclient /TopStor/etcdgetlocal.py clusternode`
myhostip=`docker exec etcdclient /TopStor/etcdgetlocal.py clusternodeip`
echo $leader | grep $myhost
if [ $? -eq 0 ];
then
	etcdip=$leaderip
else
	etcdip=$myhostip
fi
echo '############################################################################################################################################'
echo node identities
echo myhost = $myhost
echo myhost ip = $myhostip
echo leader  = $leader 
echo clusterip = $leaderip
echo system version = `git show | grep commit`
echo '############################################################################################################################################'
echo Running containers
docker ps
echo '############################################################################################################################################'
echo Found disks
lsscsi -is | grep LIO
echo '############################################################################################################################################'
echo Found iscsi sessions in other nodes:
/pace/iscsirefresh.sh $etcdip `hostname`
echo '############################################################################################################################################'
echo Presented Luns to other nodes:
targetcli ls
echo '############################################################################################################################################'
echo Running local pools
zpool status
echo '############################################################################################################################################'
echo Not imported pools
zpool import 
echo '############################################################################################################################################'
echo Running local Volumes
zfs list -oname,used,avail,refer,creation
echo '############################################################################################################################################'
echo Running snapshots 
zfs list -t snapshot -oname,creation,used
echo '############################################################################################################################################'
echo Running important services
ps -ef | egrep 'zfsping|loop|iscsiwatch'
echo '############################################################################################################################################'
echo Running system services
systemctl status --no-pager
systemctl list-units --state=failed
echo '############################################################################################################################################'
echo admin status in registry:
./etcdget.py $leaderip user admin
echo '--------'
./etcdget.py $etcdip user admin 
echo '############################################################################################################################################'
echo Active Nodes  registry:
./etcdget.py $leaderip Active --prefix
echo '--------'
./etcdget.py $etcdip Active --prefix
echo '############################################################################################################################################'
echo Known running Nodes in the registry registry:
./etcdget.py $leaderip ready  --prefix
echo '--------'
./etcdget.py $etcdip ready  --prefix
echo '############################################################################################################################################'
echo Users sync between nodes:
./etcdget.py $leaderip user  --prefix | wc -l
echo '--------'
./etcdget.py $etcdip user --prefix | wc -l
echo '############################################################################################################################################'
echo Groups  sync between nodes:
./etcdget.py $leaderip group  --prefix | wc -l
echo '--------'
./etcdget.py $etcdip group --prefix | wc -l
echo '############################################################################################################################################'
echo Host device registry 
./etcdget.py $leaderip host  --prefix 
echo '############################################################################################################################################'
echo Pools identified in registry:
./etcdget.py $leaderip pool  --prefix 
echo '--------'
./etcdget.py $etcdip pool  --prefix 
echo '############################################################################################################################################'
echo Volumes identified in registry:
./etcdget.py $leaderip vol  --prefix | masksecrets
echo '############################################################################################################################################'
echo Replication partners
./etcdget.py $leaderip Partner --prefix | masksecrets
echo '--------'
./etcdget.py $etcdip Partner  --prefix | masksecrets
echo '############################################################################################################################################'
echo Known Replication Partners
./etcdget.py $etcdip repli --prefix
echo '############################################################################################################################################'
echo Active Tunnels
/TopStor/activatetunnels.sh $leaderip
echo '############################################################################################################################################'
echo sync request status
/pace/etcdget.py $leaderip sync --prefix | grep -v initial | masksecrets
echo '############################################################################################################################################'
echo syncing result 
/pace/checksyncs.py syncrequest $leaderip $myhost 
echo '############################################################################################################################################'
