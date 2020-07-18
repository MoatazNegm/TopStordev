#!/bin/sh
export ETCDCTL_API=3
enpdev='eno1'
myip=`echo $@ | awk '{print $1}'`;
pool=`echo $@ | awk '{print $2}'`;
i=`echo $@ | awk '{print $3}'`
resname=`echo $i | awk -F'/' '{print $1}'`
newright=`echo $i | cut -d/ -f2-` 
echo newright=$newright
ipaddr=`echo $@ | awk '{print $4}'`
ipsubnet=`echo $@ | awk '{print $5}'`
echo $@ > /root/nfsparam
mounts=`echo $newright |sed 's/\// /g'| cut -f2-`
mount=''
for x in $mounts; 
do
 mount=$mount'-v /'$pool'/'$x':/'$pool'/'$x':rw '
done
/sbin/pcs resource create $resname ocf:heartbeat:IPaddr2 ip=$ipaddr nic=$enpdev cidr_netmask=$ipsubnet op monitor interval=5s on-fail=restart
/sbin/pcs resource group add ip-all $resname 
docker stop $resname
docker rm $resname
 #yes | cp /etc/{passwd,group,shadow} /etc
docker run -d $mount -v /TopStordata/exports.$ipaddr:/etc/exports:ro \
 --cap-add SYS_ADMIN -p $redipaddr:2049:2049  -p $ipaddr:2049:2049/udp \
 -p $ipaddr:32765:32765 -p $ipaddr:32765:32765/udp \
 -p $ipaddr:111:111 -p $ipaddr:111:111/udp \
 -p $ipaddr:32767:32767 -p $ipaddr:32767:32767/udp \
 -v /etc/passwd:/etc/passwd:rw \
 -v /etc/group:/etc/group:rw \
 -v /etc/shadow:/etc/shadow:rw \
 --name $resname 10.11.11.124:5000/nfs
