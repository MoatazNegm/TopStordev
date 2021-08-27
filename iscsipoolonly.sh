#!/bin/sh
cd /TopStor
export ETCDCTL_API=3
enpdev='eno1'
pool=`echo $@ | awk '{print $1}'`;
i=`echo $@ | awk '{print $2}'`
resname=`echo $i | awk -F'/' '{print $1}'`
newright=`echo $i | cut -d/ -f2-` 
echo newright=$newright
ipaddr=`echo $@ | awk '{print $3}'`
ipsubnet=`echo $@ | awk '{print $4}'`
portalport=`echo $@ | awk '{print $5}'`
echo $@ > /root/iscsiparam
mounts=`echo $newright |sed 's/\// /g'| cut -f2-`
mount=''
rm -rf /TopStordata/tempiscsi.$ipaddr
for x in $mounts; 
do
 mount=$mount'-v /'$pool'/'$x':/'$pool'/'$x':rw '
 cat /TopStordata/iscsi.$x >> /TopStordata/tempiscsi.$ipaddr
done
echo mount=$mount
/sbin/pcs resource create $resname ocf:heartbeat:IPaddr2 ip=$ipaddr nic=$enpdev cidr_netmask=$ipsubnet op monitor interval=5s on-fail=restart
/sbin/pcs resource group add ip-all $resname 
cp /TopStordata/tempiscsi.$ipaddr  /TopStordata/iscsi.$ipaddr

