#!/bin/sh
cd /TopStor
export ETCDCTL_API=3
enpdev='enp0s8'
leaderip=`echo $@ | awk '{print $1}'`
pool=`echo $@ | awk '{print $2}'`
vol=`echo $@ | awk '{print $3}'`
volip=`echo $@ | awk '{print $4}'`
vtype=`echo $@ | awk '{print $5}'`
echo $@ > /root/`basename "$0"`

docker exec etcdclient /TopStor/logqueue.py `basename "$0"` running $userreq
/TopStor/etcddel.py $leaderip vol $vol
/TopStor/etcddel.py $leaderip replivol $vol
/TopStor/etcddel.py $leaderip size $vol 
#/TopStor/deltolocal.py size $vol 
#/TopStor/deltolocal.py vol $vol 
/TopStor/crondelete $vol
rm -rf /TopStordata/smb.${volip}.new
echo vol = $vol
/TopStor/delblock.py start${vol}_only stop${vol}_only /TopStordata/smb.$volip  ;
rm -rf /TopStordata/smb.$vol
rm -rf /$pool/smb.$vol
rm -rf /TopStordata/tempsmb.$volip
rm -rf /TopStordata/smb.$volip
cat /TopStordata/smb.${volip}.new
cat /TopStordata/smb.${volip}.new > /TopStordata/smb.${volip}
resname=$vtype'-'$volip
resname=`docker ps | grep $volip | awk '{print $NF}'`
docker  rm -f $resname 
cat /TopStordata/smb.$volip | grep start | grep only
if [ $? -ne 0 ]
then 
  nmcli conn mod cmynode -ipv4.addresses $volip 
  # QSD5.337 (container flavour): the address is stored as <ip>/<prefix>, so the removal above did not match and the home
  # address stayed on cmynode/bond0 (answering ping for minutes): remove it with its prefix, then from the live interface
  [ -f /TopStor/flavor.sh ] && . /TopStor/flavor.sh
  if is_container 2>/dev/null && [ -n "$volip" ]; then
   for a in `nmcli -g ipv4.addresses conn show cmynode | tr ',' ' '`; do
    case $a in
     $volip/*) nmcli conn mod cmynode -ipv4.addresses $a ;;
    esac
   done
   for a in `ip -o -4 addr show | awk -v ip=$volip '{split($4,a,"/"); if (a[1]==ip) print $2"|"$4}'`; do
    ip addr del ${a#*|} dev ${a%|*}
   done
  fi
  nmcli conn up cmynode
  rm -rf /TopStordata/smb.$volip;
else
 mounts=`cat /TopStordata/smb.$volip | grep '\[' | sed 's/\[//g' | sed 's/\]//g' | sed ':a;N;$!ba;s/\n/,/g'`
 echo mounts=$mounts
 mount=''
 for x in $mounts; 
 do
  mount=$mount'-v /'$pool'/'$x':/'$pool'/'$x':rw '
 done
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
fi
/TopStor/etcddel.py $leaderip vol $vol
/TopStor/etcddel.py $leaderip replivol $vol
# QSD5.337: nothing of the address' share is left behind (delblock.py rewrites .new; the lock came from cifs.sh)
if [ -n "$volip" ] && [ ! -s /TopStordata/smb.$volip ]; then
 rm -f /TopStordata/smb.${volip}.new /TopStordata/cifs.${volip}.lock /TopStordata/smb.$volip
fi
 docker exec etcdclient /TopStor/logqueue.py `basename "$0"` finish $userreq
