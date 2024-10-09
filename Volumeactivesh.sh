#!/bin/sh
export ETCDCTL_API=3
cd /TopStor/
echo $@ > /root/volumeactivesh
leaderip=`echo $@ | awk '{print $1}'`;
myhost=`echo $@ | awk '{print $2}'`;
pDG=`echo $@ | awk '{print $3}'`;
name=`echo $@ | awk '{print $4}'`;
prot=`echo $@ | awk '{print $5}'`;
active=`echo $@ | awk '{print $6}'`;
#ipaddr=` echo $@ | awk '{print $7}'`;
ipaddr=`zfs get -H ip:addr $pDG/$name | awk '{print $3}'`
userreq=` echo $@ | awk '{print $8}'`;
privilege=$prot;
contrun=`./privthis.sh $privilege $userreq`;
if [[ $contrun == 'true' ]]
then
 docker exec etcdclient /TopStor/logqueue.py `basename "$0"` running $userreq
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
 echo prot=$prot, $active
 echo $prot | grep CIFS
 if [ $? -eq 0 ]
 then
  echo $active | grep disabled
  if [ $? -eq 0 ]
  then
   echo will disable $name
   sed -i 's/active/disabled/g' /$pDG/smb.$name
   dockerps=`docker ps | grep -w $ipaddr | awk '{print $1}'`
   echo -----$dockerps 
   docker rm -f $dockerps 2>/dev/null
   zfs set status:mount=disabled $pDG/$name
   zfs unmount -f $pDG/$name
  else
   #dockerps=`docker ps | grep -w $ipaddr | awk '{print $1}'`
   #docker rm -f $dockerps 2>/dev/null
   sed -i 's/disabled/active/g' /$pDG/smb.$name*
   zfs mount $pDG/$name
   zfs set status:mount=active $pDG/$name
  fi
 fi
 echo $prot | grep NFS 
 if [ $? -eq 0 ]
 then
  echo $active | grep disabled
  if [ $? -eq 0 ]
  then
   sed -i 's/active/disabled/g' /$pDG/exports.$name
   zfs set status:mount=disabled $pDG/$name
   zfs unmount -f $pDG/$name
  else
   sed -i 's/disabled/active/g' /$pDG/exports.$name*
   zfs mount $pDG/$name
   zfs set status:mount=active $pDG/$name
  fi
 fi
 /TopStor/etcdput.py $etcd dirty/volume 0     
fi
 /pace/VolumeCheck.py $leaderip $myhost
 docker exec etcdclient /TopStor/logqueue.py `basename "$0"` stop $userreq
