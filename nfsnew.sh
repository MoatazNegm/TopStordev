#!/bin/sh

cd /TopStor
export ETCDCTL_API=3
echo $@ > /root/nfshtmp
echo I am here
echo param= $@

leaderip=`echo $@ | awk '{print $1}'`
resname=`echo $@ | awk '{print $2}'`
mounts=`echo $@ | awk '{print $3}' | sed 's/\-v/ \-v /g'`
ipaddr=`echo $@ | awk '{print $4}'`
ipsubnet=`echo $@ | awk '{print $5}'`
vtype=`echo $@ | awk '{print $6}'`
share=`echo $@ | awk '{print $7}'`
writes=`echo $@ | awk '{print $8}'`
pool='/'`echo $share | awk -F'/' '{print $2}'`
volume=`echo $share | awk -F'/' '{print $3}'`
echo params $@ > /root/nfstmp
echo name $resname >> /root/nfstmp
echo mounts $mounts >> /root/nfstmp
echo ip and subnet $ipaddr $ipsubnet >> /root/cifstmp
# QSD5.337 (test 646 QX-047 step 3): one rebuild of an address container at a time. VolumeChangeNFS (address change) and the
# VolumeCheck pass both started nfsnew.sh for the same new address in parallel. The lock is /tmp/shareaddr.<ip>.lock; a caller
# that already holds it (VolumeChangeNFS, VolumeCheck.py) names the address in SHAREADDR_LOCK. A run that had to wait for the
# lock finds the container of the address already running with all its mounts and leaves it alone.
case " $SHAREADDR_LOCK " in
 *" $ipaddr "*) ;;
 *)
  exec 8>/tmp/shareaddr.$ipaddr.lock
  if ! flock -n 8;
  then
   flock -w 120 8
   if docker ps --format '{{.Names}}' | grep -qxF "$resname";
   then
    insp=`docker inspect $resname 2>/dev/null`
    allin=1
    for m in $mounts; do [ "$m" = '-v' ] && continue; echo "$insp" | grep -qF "\"${m%%:*}\"" || allin=0; done
    if [ $allin -eq 1 ];
    then
     echo `date +%T` $resname already rebuilt by the lock holder, skipped >> /root/nfshtmp
     exit 0
    fi
   fi
  fi
  ;;
esac
docker rm -f $resname
# QSD5.337: the address is no longer removed and re-added around the rebuild with "nmcli conn up cmynode" (2 re-activations of
# bond0 per rebuild, all node/cluster addresses down each time): shareaddr.sh adds it live only when it is not on the node.
# Wait only until the removed container's listeners on the address ports are gone (docker run -p binds them again).
counter=20
while [ $counter -gt 1 ];
do
	netstat -ant | awk -v a="$ipaddr" '$6=="LISTEN" && ($4==a":2049" || $4==a":20048")' | grep -q .
	if [ $? -eq 0 ];
	then
		counter=$((counter-1))
		sleep 1
	else
		counter=0
	fi
done
flag=0
/TopStor/shareaddr.sh add $ipaddr $ipsubnet
	writes2=${writes#_vol_}
	while [[ $writes2 == *_vol_* ]]; do
		current_volinfo=${writes2%%_vol_*}
		vol=`echo $current_volinfo | awk -F'_u_' '{print $1}'`
		rootname=`echo $current_volinfo | awk -F'_u_' '{print $2}' | awk -F':' '{print $1}'`
		rootid=`echo $current_volinfo | awk -F'_u_' '{print $2}' | awk -F':' '{print $2}'`
		groupname=`echo $current_volinfo | awk -F'_u_' '{print $3}' | awk -F':' '{print $1}'`
		groupid=`echo $current_volinfo | awk -F'_u_' '{print $3}' | awk -F':' '{print $2}'`
		echo $rootname , $rootid , $groupname , $groupid, $vol
		echo $rootname | grep -w root
		if [ $? -ne 0 ];
		then
			#docker exec $resname adduser $rootname -H -D -s /sbin/nologin -u $rootid
			sed -i "/$rootname/d" $pool'/user_'$volume
			echo "$rootname:x:$rootid:$rootid:$rootname:/NoHome:/sbin/nologin" >> $pool'/user_'$volume
		fi	
		echo $groupname | grep -w root
		if [ $? -ne 0 ];
		then
			echo $groupname | grep -w $rootname
			if [ $? -ne 0 ];
			then
				cat $pool'/group_'$volume | grep -w $groupname
				if [ $? -ne 0 ];
				then
			#		docker exec $resname addgroup $groupname -g $groupid
					#sed -i "/$groupname/d" $pool'/group_'$volume
					echo $groupname:x:$groupid: >> $pool'/group_'$volume
				fi
			fi
		fi	
		writes2=${writes2#*_vol_}
	done

docker run -d $mounts --rm --privileged \
  		-e "HOSTIP=$ipaddr"  \
		-e SHARED_DIRECTORY=$share \
  		-p $ipaddr:2049:2049/tcp \
  		-p $ipaddr:20048:20048/tcp \
  		-v /TopStor/nfsd.sh:/usr/bin/nfsd.sh:ro \
  		-v /TopStor/:/TopStor \
		-v $pool'/user_'$volume:/etc/passwd:rw \
		-v $pool'/group_'$volume:/etc/group:rw \
  		--name $resname itsthenetwork/nfs-server-alpine
# portmap v2 on the volume ip: the container's rpcbind answers with its private address (see nfsportmap.py), exits with the container
pkill -f "nfsportmap.py $ipaddr " 
nohup setsid python3 /TopStor/nfsportmap.py $ipaddr $resname >/dev/null 2>&1 8>&- &
counter=20
while [ $counter -gt 1 ];
do
	counter=$((counter-1))
	sleep 1
	docker logs $resname | grep 'Startup successful'
	if [ $? -eq 0 ];
	then
		counter=0
	fi
done
if [ $counter -eq 1 ];
then
	docker logs $resname > /root/failedNFScontainer
else
	writes=${writes#_vol_}
	while [[ $writes == *_vol_* ]]; do
		current_volinfo=${writes%%_vol_*}
		vol=`echo $current_volinfo | awk -F'_u_' '{print $1}'`
		rootname=`echo $current_volinfo | awk -F'_u_' '{print $2}' | awk -F':' '{print $1}'`
		rootid=`echo $current_volinfo | awk -F'_u_' '{print $2}' | awk -F':' '{print $2}'`
		groupname=`echo $current_volinfo | awk -F'_u_' '{print $3}' | awk -F':' '{print $1}'`
		groupid=`echo $current_volinfo | awk -F'_u_' '{print $3}' | awk -F':' '{print $2}'`
		
 		docker exec $resname chown $rootname $vol 
 		docker exec $resname chgrp $groupname $vol 
 		docker exec $resname chmod 770 $vol 
 		docker exec $resname chmod g+s $vol 
 		docker exec $resname chmod u+s $vol 
		writes=${writes#*_vol_}

		/TopStor/TenantUserList $leaderip $volume $pool
		
	done
# Step 1: Extract the list of usernames and IDs after the user "rpc"

fi
