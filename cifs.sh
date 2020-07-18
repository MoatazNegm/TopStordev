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
docker rm -f `docker ps -a | grep -v Up | grep $ipaddr | awk '{print $1}'` 2>/dev/null
clearvol=`./prot.py clearvol $vol | awk -F'result=' '{print $2}'`
if [ $clearvol != '-1' ];
then
 docker stop $clearvol 
 docker container rm $clearvol 
 /sbin/pcs resource delete --force $clearvol  2>/dev/null
fi
redvol=`./prot.py redvol $vol | awk -F'result=' '{print $2}'`
if [ $redvol != '-1' ];
then
 redipaddr=`echo $redvol | awk -F'-' '{print $NF}'`
 echo redvol=$redvol redipaddr=$redipaddr
 /TopStor/delblock.py start${vol}_only stop${vol}_only /TopStordata/smb.${ipaddr}  ;
 cp /TopStordata/smb.${redipaddr}.new /TopStordata/smb.${ipaddr};
 docker exec -it $redvol smbcontrol smbd reload-config
fi
rightip=`/pace/etcdget.py ipaddr/$ipaddr/$ipsubnet`
echo  rightip=$rightip
resname=`echo $rightip | awk -F'/' '{print $1}'`
echo $rightip | grep -w '\-1' 
if [ $? -eq 0 ];
then
 resname=$vtype-$pool-$ipaddr
 echo resname=$resname
 /pace/etcdput.py ipaddr/$ipaddr/$ipsubnet $resname/$vol
 /pace/broadcasttolocal.py ipaddr/$ipaddr/$ipsubnet $resname/$vol 
 docker stop $resname  2>/dev/null
 docker container rm -f $resname 2>/dev/null
 /sbin/pcs resource delete --force $resname  2>/dev/null
 /sbin/pcs resource create $resname ocf:heartbeat:IPaddr2 ip=$ipaddr nic=$enpdev cidr_netmask=$ipsubnet op monitor interval=5s on-fail=restart
 /sbin/pcs resource group add ip-all $resname 
# yes | cp /etc/{passwd,group,shadow} /opt
 cp /TopStor/smb.conf /TopStordata/smb.$ipaddr
 cat /TopStordata/smb.${vol}>> /TopStordata/smb.$ipaddr
 cp /TopStor/VolumeCIFSupdate.sh /etc/
 docker run -d -v /$pool/$vol:/$pool/$vol:rw --privileged \
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
 sleep 3
 docker exec $resname sh /hostetc/VolumeCIFSupdate.sh
else
 echo 'multiple vols'
 newright=${rightip}'/'$vol 
 mounts=`echo $newright |sed 's/\// /g'| awk '{$1=""; print}'`
 mount=''
 rm -rf /TopStordata/tempsmb.$ipaddr
 for x in $mounts; 
 do
  mount=$mount'-v /'$pool'/'$x':/'$pool'/'$x':rw '
  cat /TopStordata/smb.$x >> /TopStordata/tempsmb.$ipaddr
 done
 /pace/etcdput.py ipaddr/$ipaddr/$ipsubnet $newright 
 /pace/broadcasttolocal.py ipaddr/$ipaddr/$ipsubnet $newright
 cp /TopStordata/tempsmb.$ipaddr  /TopStordata/smb.$ipaddr
 cp /TopStor/VolumeCIFSupdate.sh /etc/
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
  -v /etc/:/hostetc/   \
  -v /var/lib/samba/private:/var/lib/samba/private:rw \
  --name $resname 10.11.11.124:5000/smb
  sleep 3
  docker exec $resname sh /hostetc/VolumeCIFSupdate.sh
fi

