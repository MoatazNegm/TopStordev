#!/bin/sh
export ETCDCTL_API=3
enpdev='eno1'
pool=`echo $@ | awk '{print $1}'`
vol=`echo $@ | awk '{print $2}'`
ipaddr=`echo $@ | awk '{print $3}'`
ipsubnet=`echo $@ | awk '{print $4}'`
echo $@ > /root/nfsparam
docker rm -f `docker ps -a | grep -v Up | grep $ipaddr | awk '{print $1}'` 2>/dev/null
clearvol=`./prot.py clearvol $vol | awk -F'result=' '{print $2}'`
if [ $clearvol != '-1' ];
then
 /sbin/pcs resource delete --force $clearvol  2>/dev/null
fi
redvol=`./prot.py redvol $vol | awk -F'result=' '{print $2}'`
if [ $redvol != '-1' ];
then
 redipaddr=`echo $redvol | awk -F'/' '{print $1}' | awk -F'-' '{print $NF}'`
 echo iam here 1
 /TopStor/delblock.py ${vol} ${vol} /TopStordata/exports.${ipaddr}  ;
 cp /TopStordata/exports.${ipaddr}.new /TopStordata/exports.${ipaddr};
 cat /etc/exports | grep -v $vol  > /etc/exports
 cat /TopStordata/exports.${ipaddr} >> /etc/exports ;
 systemctl start nfs-server
 systemctl reload nfs-server
 resname=`echo $redvol | awk -F'/' '{print $1}'`
 newright=$redvol 
 mounts=`echo $newright |sed 's/\// /g'| awk '{$1=""; print}'`
 mount=''
 for x in $mounts; 
 do
  mount=$mount'-v /'$pool'/'$x':/'$pool'/'$x':rw '
 done
fi 
rightip=`/pace/etcdget.py ipaddr/$ipaddr/$ipsubnet`
resname=`echo $rightip | awk -F'/' '{print $1}'`
 echo iam here 2
 resname=nfs-$pool-$ipaddr
 /pace/etcdput.py ipaddr/$ipaddr/$ipsubnet $resname/$vol 
 /pace/broadcasttolocal.py ipaddr/$ipaddr/$ipsubnet $resname/$vol 
 #yes | cp /etc/{passwd,group,shadow} /etc
 cp /TopStordata/exports.${vol} /TopStordata/exports.$ipaddr; 
 cat /etc/exports | grep -v $vol  > /TopStordata/exports;
 cp /TopStordata/exports  /etc/exports;
 cat /TopStordata/exports.${ipaddr} >> /etc/exports ;
 systemctl reload nfs-server
 /sbin/pcs resource delete --force $resname  2>/dev/null
 /sbin/pcs resource create $resname ocf:heartbeat:IPaddr2 ip=$ipaddr nic=$enpdev cidr_netmask=$ipsubnet op monitor interval=5s on-fail=restart
 /sbin/pcs resource group add ip-all $resname
