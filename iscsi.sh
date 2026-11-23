#!/bin/sh
cd /TopStor
export ETCDCTL_API=3
# the trace without the CHAP secret ($9; QSD5.341 test 653)
echo $@ | awk '{ if (NF >= 9) $9 = "***"; print }' > /root/iscsiparam

resname=`echo $@ | awk '{print $1}'`
#mounts=`echo $@ | awk '{print $2}' | sed 's/\-v/ \-v /g'`
vol=`echo $@ | awk '{print $2}' | awk -F'/' '{print $2}' `
pool=`echo $@ | awk '{print $2}' | awk -F'/' '{print $1}' `
ipaddr=`echo $@ | awk '{print $3}'`
ipsubnet=`echo $@ | awk '{print $4}'`
vtype=`echo $@ | awk '{print $5}'`
#docker rm -f $resname
# QSD5.337 (test 646): share address live via shareaddr.sh, no "nmcli conn up cmynode" (bond0 re-activation drops every address)
/TopStor/shareaddr.sh add $ipaddr $ipsubnet
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

echo /pace/addzfsvolumeastarget.sh $pool ${vol} $ipaddr $portalport $targetiqn $chapuser '***'
 for i in $(echo $targetiqn | sed "s/,/ /g")
 do
#pdhcp2524812990 pool1is_250024055 10.11.11.11 3263 iqn.1991-05.com.microsoft:desktop-jckvhk3 <chapuser> <chappas token>
  /pace/addzfsvolumeastarget.sh $pool $vol $ipaddr $portalport $i $chapuser $chappas 

    # call your procedure/other scripts here below
 done
#/pace/addzfsvolumeastarget.sh $pool ${vol} $ipaddr $portalport $targetiqn $chapuser $chappas
