#!/bin/sh
cd /TopStor
echo $@ > /root/cifsmember
export ETCDCTL_API=3
enpdev='enp0s8'
leaderip=`echo $@ | awk '{print $1}'`
pool=`echo $@ | awk '{print $2}'`
vol=`echo $@ | awk '{print $3}'`
ipaddr=`echo $@ | awk '{print $4}'`
ipsubnet=`echo $@ | awk '{print $5}'`
vtype=`echo $@ | awk '{print $6}'`
domain=`echo $@ | awk '{print $7}'`
domainsrvn=`echo $@ | awk '{print $8}'`
domainsrvi=`echo $@ | awk '{print $9}'`
domadmin=`echo $@ | awk '{print $10}'`
adminpass=`echo $@ | awk '{print $11}'`
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


echo $@ > /root/cifsmember
echo $@ > /root/cifsparam
allvols=`./etcdget.py $etcd volumes --prefix`
replivols=`echo $allvols | grep $vol`
echo $replivols | grep active
if [ $? -ne 0 ];
then
 exit
fi

rightip=`/pace/etcdget.py $etcd ipaddr/$myhost $vtype-$ipaddr | grep -v $vol`
otherip=`/pace/etcdget.py $etcd ipaddr $vtype-$ipaddr | grep -v $myhost | wc -c`
othervtype=`/pace/etcdget.py $etcd ipaddr $ipaddr | grep -v $vtype | wc -c` 
 docker exec etcdclient /TopStor/logqueue.py `basename "$0"` running $userreq
if [ $otherip -ge 5 ];
then 
 echo another host is holding the ip
 echo otherip=$otherip
 docker exec etcdclient /TopStor/logqueue.py `basename "$0"` stop $userreq
 exit
fi
if [ $othervtype -ge 5 ];
then 
 echo the ip is used by another protocol 
 docker exec etcdclient /TopStor/logqueue.py `basename "$0"` stop $userreq
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
 rightvols=`/pace/etcdget.py $etcd ipaddr/$myhost/$ipaddr/$ipsubnet | sed "s/$resname\///g"`'/'$vol
fi
 echo /pace/etcdput.py $leaderip ipaddr/$myhost/$ipaddr/$ipsubnet $resname/$rightvols
 /pace/etcdput.py $leaderip ipaddr/$myhost/$ipaddr/$ipsubnet $resname/$rightvols
 stamp=`date +%s`;
 echo /pace/etcdput.py $leaderip sync/ipaddr/request ipaddr_$stamp
 /pace/etcdput.py $leaderip sync/ipaddr/request ipaddr_$stamp
 echo /pace/etcdput.py $leaderip sync/ipaddr/request/$leader ipaddr_$stamp
 /pace/etcdput.py $leaderip sync/ipaddr/request/$leader ipaddr_$stamp
 #/pace/broadcasttolocal.py ipaddr/$myhost/$ipaddr/$ipsubnet $resname/$rightvols 
 mounts=`echo $rightvols | sed 's/\// /g'`
 echo rightvol=$rightvols
 echo mounts=$mounts
 mount=''
 rm -rf /TopStordata/tempsmb.$ipaddr
 for x in $mounts; 
 do
  replivols=`echo $allvols | grep $x`
  echo $replivols | grep active
  if [ $? -ne 0 ];
  then
   continue
  fi
  mount=$mount' -v /'$pool'/'$x':/'$pool'/'$x':rw '
  cat /TopStordata/smb.$x >> /TopStordata/tempsmb.$ipaddr
 done
 cp /TopStordata/tempsmb.$ipaddr  /TopStordata/smb.$ipaddr
 dockers=`docker ps -a`
 echo $dockers | grep $resname
 if [ $? -eq 0 ];
 then
  docker stop $resname 
  docker rm -f $resname
 fi
 membername=`echo $vol | awk -F'_' '{print $1}'`
 wrkgrp=`echo $domain | awk -F'\.' '{print $1}'`  
 echo -e 'notyet=1 \nwhile [ $notyet -eq 1 ];\ndo\nsleep 3' > /etc/smb${vol}.sh
 echo -e 'cat /etc/samba/smb.conf | grep' "'\[public\]'" >> /etc/smb${vol}.sh
 echo -e 'if [ $? -eq 0 ];\nthen' >> /etc/smb${vol}.sh
 echo -e ' cat /etc/samba/smb.conf | grep' "'\[private\]'" >> /etc/smb${vol}.sh
 echo -e ' if [ $? -eq 0 ];\nthen' >> /etc/smb${vol}.sh
 echo -e '  cat /etc/samba/smb.conf | grep' "'\[home\]'" >> /etc/smb${vol}.sh
 echo -e '  if [ $? -eq 0 ];\nthen\nnotyet=0\nfi\nfi\nfi\ndone' >> /etc/smb${vol}.sh
 echo  "sed -i -e '51,1000d' /etc/samba/smb.conf"  >> /etc/smb${vol}.sh
 echo  "cat /etc/smb.conf >> /etc/samba/smb.conf"  >> /etc/smb${vol}.sh
 echo  "service samba --full-restart"  >> /etc/smb${vol}.sh
 chmod +w /etc/smb${vol}.sh
 sync
 cp /etc/resolv.conf /TopStordata/ 
 echo nameserver $domainsrvi > /etc/resolv.conf
#  -e TZ=Etc/UTC \
 #adminpass=`echo $adminpass | sed 's/\@\@sep/\//g' | sed ':a;N;$!ba;s/\n/ /g'`
 adminpass=`echo $adminpass | sed 's/\@\@sep/\//g'`
 adminpass=`./decthis.sh $domain $adminpass | awk -F'_result' '{print $2}' `
 docker run -d  $mount --privileged --rm --add-host "${membername}.$domain ${membername}":$ipaddr  \
  --hostname ${membername} \
  -v /etc/localtime:/etc/localtime:ro \
  -v /etc/:/hostetc/   \
  -v /TopStordata/smb.${ipaddr}:/etc/smb.conf:rw \
  -e DOMAIN_NAME=$domain \
  -e ADMIN_SERVER=$domainsrvi \
  -e WORKGROUP=$wrkgrp  \
  -e AD_USERNAME=$domadmin \
  -e AD_PASSWORD=$adminpass \
  -p $ipaddr:137:137/udp \
  -p $ipaddr:138:138/udp \
  -p $ipaddr:139:139/tcp \
  -p $ipaddr:445:445/tcp \
  --name $resname 10.11.11.124:5000/membersmb 
cat /TopStordata/resolv.conf > /etc/resolv.conf
docker exec $resname sh /hostetc/smb${vol}.sh &


 docker exec etcdclient /TopStor/logqueue.py `basename "$0"` stop $userreq
