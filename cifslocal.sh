#!/bin/sh
cd /TopStor
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
echo $@ > /root/cifslocalparam
mounts=`echo $newright |sed 's/\// /g'| cut -f2-`
mount=''
rm -rf /TopStordata/tempsmb.$ipaddr
for x in $mounts; 
do
 mount=$mount'-v /'$pool'/'$x':/'$pool'/'$x':rw '
 cat /TopStordata/smb.$x >> /TopStordata/tempsmb.$ipaddr
done
echo mount=$mount
/sbin/pcs resource create $resname ocf:heartbeat:IPaddr2 ip=$ipaddr nic=$enpdev cidr_netmask=$ipsubnet op monitor interval=5s on-fail=restart
/sbin/pcs resource group add ip-all $resname 
cp /TopStordata/tempsmb.$ipaddr  /TopStordata/smb.$ipaddr
yes | cp /etc/{passwd,group,shadow} /etc
docker stop $resname
docker rm $resname
docker run -d $mount --privileged \
 -e "HOSTIP=$ipaddr"  \
 -p $ipaddr:135:135 \
 -p $ipaddr:137-138:137-138/udp \
 -p $ipaddr:139:139 \
 -p $ipaddr:445:445 \
 -v /etc/localtime:/etc/localtime:ro \
 -v /TopStordata/smb.${ipaddr}:/config/smb.conf:rw \
  -v /etc:/hostetc/    \
 -v /var/lib/samba/private:/var/lib/samba/private:rw \
 --name $resname 10.11.11.124:5000/smb

