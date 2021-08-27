#!/bin/sh
export ETCDCTL_API=3
enpdev='eno1'
pool=`echo $@ | awk '{print $1}'`;
i=`echo $@ | awk '{print $2}'`
resname=`echo $i | awk -F'/' '{print $1}'`
newright=`echo $i | cut -d/ -f2-` 
echo newright=$newright
ipaddr=`echo $@ | awk '{print $3}'`
ipsubnet=`echo $@ | awk '{print $4}'`
echo $@ > /root/nfsparam
mounts=`echo $newright |sed 's/\// /g'| cut -f2-`
mount=''
for x in $mounts; 
do
 mount=$mount'-v /'$pool'/'$x':/'$pool'/'$x':rw '
done
/sbin/pcs resource create $resname ocf:heartbeat:IPaddr2 ip=$ipaddr nic=$enpdev cidr_netmask=$ipsubnet op monitor interval=5s on-fail=restart
/sbin/pcs resource group add ip-all $resname 
cat /etc/exports | grep -v $vol  > /etc/exports
cat /TopStordata/exports.${ipaddr} >> /etc/exports ;
systemctl reload nfs-server
