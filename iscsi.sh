#!/bin/sh
cd /TopStor
export ETCDCTL_API=3
echo $@ > /root/iscsiparam

resname=`echo $@ | awk '{print $1}'`
#mounts=`echo $@ | awk '{print $2}' | sed 's/\-v/ \-v /g'`
vol=`echo $@ | awk '{print $2}' | awk -F'/' '{print $2}' `
pool=`echo $@ | awk '{print $2}' | awk -F'/' '{print $1}' `
ipaddr=`echo $@ | awk '{print $3}'`
ipsubnet=`echo $@ | awk '{print $4}'`
vtype=`echo $@ | awk '{print $5}'`
#docker rm -f $resname
/TopStor/cmynodeaddr.sh add $ipaddr $ipsubnet    # QSD5.352 (QC 698): locked, checked, retried
enpdev='enp0s8'
portalport=`echo $@ | awk '{print $6}'`
targetiqn=`echo $@ | awk '{print $7}'`
chapuser=`echo $@ | awk '{print $8}'`
chappas=`echo $@ | awk '{print $9}'`
myhost=`docker exec etcdclient /TopStor/etcdgetlocal.py clusternode`
	myhostip=`docker exec etcdclient /TopStor/etcdgetlocal.py clusternodeip`
	leader=`docker exec etcdclient /TopStor/etcdgetlocal.py leader`
	echo $leader | grep $myhost
	if [ $? -ne 0 ];
	then
 		etcd=$myhostip
	else
 		etcd=$leaderip
 	fi

echo /pace/addzfsvolumeastarget.sh $pool ${vol} $ipaddr $portalport $targetiqn $chapuser $chappas
 for i in $(echo $targetiqn | sed "s/,/ /g")
 do
#pdhcp2524812990 pool1is_250024055 10.11.11.11 3263 iqn.1991-05.com.microsoft:desktop-jckvhk3 MoatazNegm MezoAdmin
  /pace/addzfsvolumeastarget.sh $pool $vol $ipaddr $portalport $i $chapuser $chappas 

    # call your procedure/other scripts here below
 done
#/pace/addzfsvolumeastarget.sh $pool ${vol} $ipaddr $portalport $targetiqn $chapuser $chappas
