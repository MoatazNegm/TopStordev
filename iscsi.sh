#!/bin/sh
cd /TopStor
export ETCDCTL_API=3
enpdev='eno1'
pool=`echo $@ | awk '{print $1}'`
vol=`echo $@ | awk '{print $2}'`
ipaddr=`echo $@ | awk '{print $3}'`
ipsubnet=`echo $@ | awk '{print $4}'`
portalport=`echo $@ | awk '{print $5}'`
targetiqn=`echo $@ | awk '{print $6}'`
chapuser=`echo $@ | awk '{print $7}'`
chappas=`echo $@ | awk '{print $8}'`
vtype='iscsi'
myhost=`hostname`
echo $@ > /root/iscsiparam
rightip=`/pace/etcdget.py ipaddr/$myhost $vtype-$ipaddr | grep -v $vol`
otherip=`/pace/etcdget.py ipaddr $vtype-$ipaddr | grep -v $myhost | wc -c`
othervtype=`/pace/etcdget.py ipaddr $ipaddr | grep -v $vtype | wc -c` 
if [ $otherip -ge 5 ];
then 
 echo another host is holding the ip
 echo otherip=$otherip
 exit
fi
if [ $othervtype -ge 5 ];
then 
 echo the ip is used by another protocol 
 /TopStor/logmsg.py ISCSIwa01 warning $userreq $ipaddr 
 exit
fi
resname=$vtype'-'$ipaddr
if [[ $rightip == '' ]];
then
 echo nothing found
 rightip=''
 rightvols=$vol
else
 echo found other vols
rightvols=`/pace/etcdget.py ipaddr/$myhost/$ipaddr/$ipsubnet | sed "s/$resname\///g"`'/'$vol
fi
 /pace/etcdput.py ipaddr/$myhost/$ipaddr/$ipsubnet $resname/$rightvols
 /pace/broadcasttolocal.py ipaddr/$myhost/$ipaddr/$ipsubnet $resname/$rightvols 
 /sbin/pcs resource delete --force $resname  2>/dev/null
 /sbin/pcs resource create $resname ocf:heartbeat:IPaddr2 ip=$ipaddr nic=$enpdev cidr_netmask=$ipsubnet op monitor interval=5s on-fail=restart
 /sbin/pcs resource group add ip-all $resname 
echo continue
echo /pace/addzfsvolumeastarget.sh $pool ${vol} $ipaddr $portalport $targetiqn $chapuser $chappas
 for i in $(echo $targetiqn | sed "s/,/ /g")
 do
#pdhcp2524812990 pool1is_250024055 10.11.11.11 3263 iqn.1991-05.com.microsoft:desktop-jckvhk3 MoatazNegm MezoAdmin
  /pace/addzfsvolumeastarget.sh $pool $vol $ipaddr $portalport $i $chapuser $chappas 

    # call your procedure/other scripts here below
 done
#/pace/addzfsvolumeastarget.sh $pool ${vol} $ipaddr $portalport $targetiqn $chapuser $chappas
