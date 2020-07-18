#!/bin/sh
enpdev='eno1'
pool=`echo $@ | awk '{print $1}'`
vol=`echo $@ | awk '{print $2}'`
ipaddr=`echo $@ | awk '{print $3}'`
ipsubnet=`echo $@ | awk '{print $4}'`
echo $@ > /root/cifsparam
docker stop cifs-$pool-$vol
docker container rm cifs-$pool-$vol
/sbin/pcs resource delete --force ip-$pool-$vol  2>/dev/null
/sbin/pcs resource create ip-$pool-$vol ocf:heartbeat:IPaddr2 ip=$ipaddr nic=$enpdev cidr_netmask=$ipsubnet op monitor interval=5s on-fail=restart
/sbin/pcs resource group add ip-all ip-$pool-$vol
docker run -d -v /$pool/$vol:/$pool/$vol --privileged \
 -e "HOSTIP=$ipaddr"  \
 -p $ipaddr:53:53 \
 -p $ipaddr:53:53/udp \
 -p $ipaddr:88:88 \
 -p $ipaddr:88:88/udp \
 -p $ipaddr:135:135 \
 -p $ipaddr:137-138:137-138/udp \
 -p $ipaddr:139:139 \
 -p $ipaddr:389:389 \
 -p $ipaddr:389:389/udp \
 -p $ipaddr:445:445 \
 -p $ipaddr:464:464 \
 -p $ipaddr:464:464/udp \
 -p $ipaddr:636:636 \
 -p $ipaddr:1024-1044:1024-1044 \
 -p $ipaddr:3268-3269:3268-3269 \
 -v /etc/localtime:/etc/localtime:ro \
 -v /TopStordata/smb${name}.conf:/etc/samba/external \
 -v /TopStordata/data${name}:/var/lib/samba \
 --name cifs-$pool-$vol 10.11.11.124:5000/samba
