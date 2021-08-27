#!/bin/sh
cd /TopStor
export ETCDCTL_API=3
enpdev='eno1'
pool=`echo $@ | awk '{print $1}'`
vol=`echo $@ | awk '{print $2}'`
ipaddr=`echo $@ | awk '{print $3}'`
ipsubnet=`echo $@ | awk '{print $4}'`
vtype=`echo $@ | awk '{print $5}'`
echo $@ > /root/cifsparam
myhost=`hostname`
#docker rm -f `docker ps -a | grep -v Up | grep $ipaddr | awk '{print $1}'` 2>/dev/null
echo cifs $@
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
 exit
fi
#clearvol=`./prot.py clearvol $vol | awk -F'result=' '{print $2}'`
#redvol=`./prot.py redvol $vol | awk -F'result=' '{print $2}'`
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
 /sbin/pcs resource create $resname ocf:heartbeat:IPaddr2 ip=$ipaddr nic=$enpdev cidr_netmask=$ipsubnet op monitor interval=5s on-fail=restart
 /sbin/pcs resource group add ip-all $resname 
 mounts=`echo $rightvols | sed 's/\// /g'`
 echo rightvol=$rightvols
 echo mounts=$mounts
 mount=''
 rm -rf /TopStortempsmb.$ipaddr
 for x in $mounts; 
 do
  mount=$mount'-v /'$pool'/'$x':/'$pool'/'$x':rw '
  cat /TopStordata/smb.$x >> /TopStordata/tempsmb.$ipaddr
 done
 echo mount=$mount
 cp /TopStordata/tempsmb.$ipaddr  /TopStordata/smb.$ipaddr
 cp /TopStor/VolumeCIFSupdate.sh /etc/
 dockers=`docker ps -a`
 echo $dockers | grep $resname
 if [ $? -eq 0 ];
 then
  docker stop $resname 
  docker rm -f $resname
 fi
 docker run -d $mount --privileged \
  -e "HOSTIP=$ipaddr"  \
  -p $ipaddr:135:135 \
  -p $ipaddr:137-138:137-138/udp \
  -p $ipaddr:139:139 \
  -p $ipaddr:445:445 \
  -v /etc/localtime:/etc/localtime:ro \
  -v /TopStordata/smb.${ipaddr}:/config/smb.conf:rw \
  -v /etc/:/hostetc/   \
  -v /var/lib/samba/private:/var/lib/samba/private:rw \
  --name $resname 10.11.11.124:5000/smb
  sleep 3
  docker exec $resname sh /hostetc/VolumeCIFSupdate.sh

