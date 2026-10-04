#!/usr/bin/sh
[ -f /TopStor/flavor.sh ] && . /TopStor/flavor.sh
fnkillall () {
process=(`ps -ef | grep $1 | grep -v color | grep -v grep | awk '{print $2}'`)
for proc in "${process[@]}"; do
 echo proc $proc
 kill -9 $proc 2>/dev/null
done
}
leader=`docker exec etcdclient /TopStor/etcdgetlocal.py leader`
leaderip=`docker exec etcdclient /TopStor/etcdgetlocal.py leaderip`
myhost=`docker exec etcdclient /TopStor/etcdgetlocal.py clusternode`
myhostip=`docker exec etcdclient /TopStor/etcdgetlocal.py clusternodeip`
echo $leader | grep $myhost
if [ $? -eq 0 ];
then
	etcdip=$leaderip
else
	etcdip=$myhostip
fi
cujobs=(`echo diskreflooper zpooltoimportlooper iscsiwatchdog zfsping topstorrecvreply receivereplylooper checksyncs syncrequestlooper selectsparelooper volumechecklooper croncalllooper selectimportlooper retryvolumedeletelooper zfstelemetrylooper`)
declare  -A cmdcjobs
cmdcjobs['iscsiwatchdog']="/TopStor/iscsiwatchdog.sh" 
is_container 2>/dev/null && cmdcjobs['iscsiwatchdoglooper']="/TopStor/iscsiwatchdoglooper.sh" 
cmdcjobs['zfsping']="/pace/zfsping.py"
cmdcjobs['topstorrecvreply']="echo"
cmdcjobs['receivereplylooper']="/TopStor/receivereplylooper.sh"
cmdcjobs['syncrequestlooper']="/pace/syncrequestlooper.sh"
cmdcjobs['selectsparelooper']="/pace/selectsparelooper.sh"
cmdcjobs['volumechecklooper']="/pace/VolumeChecklooper.sh"
cmdcjobs['diskreflooper']="/pace/diskreflooper.sh"
cmdcjobs['zpooltoimportlooper']="/pace/zpooltoimportlooper.sh"
cmdcjobs['croncalllooper']="/pace/croncalllooper.sh"
cmdcjobs['checksyncs']="echo"
cmdcjobs['retryvolumedeletelooper']="/pace/retryvolumedeletelooper.sh"
cmdcjobs['selectimportlooper']="/pace/selectimportlooper.sh"
cmdcjobs['zfstelemetrylooper']="/pace/zfstelemetrylooper.sh"

while true;
do
 flag=0
 echo docker exec etcdclient /TopStor/etcdgetlocal.py refreshdisown/$myhost \| grep yes 
 docker exec etcdclient /TopStor/etcdgetlocal.py refreshdisown/$myhost | grep yes 
 if [ $? -eq 0 ];
 then
  flag=1
  leader=`docker exec etcdclient /TopStor/etcdgetlocal.py leader`
  leaderip=`docker exec etcdclient /TopStor/etcdgetlocal.py leaderip`
  #/pace/diskref.sh $leader $leaderip $myhost $myhostip
  echo newleader  $leader $leaderip > /root/refreshdisown
  echo $leader | grep $myhost
  if [ $? -eq 0 ];
  then
	etcdip=$leaderip
  else
	etcdip=$myhostip
  fi
  echo 'SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSstart'
  cjobs=(`echo "${cujobs[@]}"`)
  docker exec etcdclient /TopStor/etcdput.py etcd refreshdisown/$myhost 0 
 fi
 while [ $flag -ne 0 ];
 do
  flag=0
  rjobs=(`echo "${cjobs[@]}"`)
  echo rjobs=$rjobs
  for job in "${rjobs[@]}";
  do
	echo '###########################################'
 	echo $job
  	flag=`docker exec etcdclient /TopStor/etcdgetlocal.py refreshdisown/$myhost`
        echo flaginfor $flag
 	fnkillall $job
 	isproc=`ps -ef | grep $job | grep -v color | grep -v grep | awk '{print $2}' | wc -l`
	if [ $isproc -eq 0 ];
	then
		cjobs=(`echo "${cjobs[@]}" | grep -v $job`)
		#cmd=`echo -e $cmdcjobs | grep $job`
		cmd=${cmdcjobs[$job]}
	 	echo $cmd $leaderip $myhost $leader $myhostip\& disown	>> /root/refreshtemp
	 	$cmd $leaderip $myhost $leader $myhostip >/dev/null & disown	
	fi
	flag=$((flag+isproc))
	echo flagwithiscproc=$flag
  	docker exec etcdclient /TopStor/etcdput.py etcd refreshdisown/$myhost $flag 
	echo flag=$flag
  done
  flag=`docker exec etcdclient /TopStor/etcdgetlocal.py refreshdisown/$myhost`
  echo flaginwhile=$flag
 done
 echo 'SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSstop'
 sleep 2
done
