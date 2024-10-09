#!/usr/bin/sh
eth1='enp0s8'
eth2='enp0s8';

# Get the current directory
ports='/TopStordata/ports'
if grep -q 'reset' /root/nodestatus; then
	pports=$(ip a | grep -Po '(?<=^\d: )[^\:]+')
	eth1=$(echo "$pports" | sed -n '2p')
	eth2=$(echo "$pports" | sed -n '2p')
	echo "$eth1" > $ports
	echo "$eth2" >> $ports
fi

# Create an empty list
eth_list=()
if [ ! -f $ports ];
then
	eth_list=("$eth1")
	eth_list+=("$eth2")
	for item in "${eth_list[@]}"; do
  		echo "$item" >> $ports
	done
else
	while read -r line; do
    		eth_list+=("$line")
	done < "$ports"
fi

# Print the list
eth1="${eth_list[0]}"
eth2="${eth_list[1]}"

modprobe bnx2
modprobe hpsa 
systemctl restart NetworkManager
myclusterf='/topstorwebetc/mycluster'
mynodef='/topstorwebetc/mynode'
myhost=`hostname`
firewall-cmd --permanent --add-service={nfs,rpc-bind,mountd}
firewall-cmd --permanent --add-port=5672/tcp
firewall-cmd --permanent --add-port=5672/udp
firewall-cmd --permanent --add-port=137/tcp
firewall-cmd --permanent --add-port=137/udp
firewall-cmd --permanent --add-port=138/tcp
firewall-cmd --permanent --add-port=138/udp
firewall-cmd --permanent --add-port=139/tcp
firewall-cmd --permanent --add-port=139/udp
firewall-cmd --permanent --add-port=445/tcp
firewall-cmd --permanent --add-port=445/udp
firewall-cmd --permanent --add-port=389/tcp
firewall-cmd --permanent --add-port=389/udp
firewall-cmd --permanent --add-port=88/tcp
firewall-cmd --permanent --add-port=88/udp
firewall-cmd  --permanent --add-port=2381-2481/tcp
firewall-cmd  --permanent --add-port=2381-2481/udp
firewall-cmd --reload
cat /etc/ssh/sshd_config | grep Gateway | grep yes 
if [ $? -ne 0 ];
then
 echo GatewayPorts yes >> /etc/ssh/sshd_config
fi
cmdline=$@
order=`cat /root/nodeconfigured`
echo l$order | grep  reset
if [ $? -eq 0 ];
then 
  cmdline='reset'
  cp /TopStordata/ports /root/
  cp /TopStordata/bootdiskf /root/
  rm -rf /TopStordata/*
  cp /root/ports /TopStordata/
  rm -rf /root/ports
  cp /root/bootdiskf /TopStordata/
  rm -rf /root/bootdiskf
  echo no > /root/nodeconfigured
fi

mypid='/TopStordata/diskchange'
echo stop stop stop stop > $mypid
cp /TopStor/101-qstor.rules /usr/lib/udev/rules.d/
udevadm control -R
sed -i 's/\=enforcing/\=disabled/g' /etc/selinux/config
echo '# init' > /etc/exports
rm -rf /TopStordata/exportip.*
echo ${myhost}$cmdline | grep reboot
if [ $? -ne 0 ];
then
 nmcli conn up mynode
 zpool export -a
fi
/usr/bin/targetcli clearconfig confirm=True	
targetcli saveconfig
echo ${myhost}$cmdline | egrep 'init|local'
if [ $? -eq 0 ];
then
	myhost='dhcp'`echo $RANDOM$RANDOM | cut -c -6`
	hostname $myhost
	echo $myhost > /etc/hostname
	echo frstreboot > /root/hostname
	echo InitiatorName=iqn.1994-05.com.redhat:$myhost > /etc/iscsi/initiatorname.iscsi
	reboot
fi
cat /root/hostname | grep frstreboot
if [ $? -eq 0 ];
then
	echo $myhost > /root/hostname
	reboot
fi
echo l$cmdline | grep restart
if [ $? -eq 0 ];
then
	/TopStor/resetdocker.sh
fi
lencmdline=`echo $cmdline | wc -w`
if [ $lencmdline -ge 1 ];
then 
	echo $cmdline | egrep 'stop|reboot|reset'
	if [ $? -eq 0 ];
	then
		/TopStor/resetdocker.sh
		echo $cmdline | grep reset
		if [ $? -eq 0 ];
		then
			rm -rf /root/node*
			rm  -rf /root/etcddata/* 
			echo yes | cp /TopStor/passwd /etc/
			echo yes | cp /TopStor/group /etc/
			echo reset > /root/nodestatus
			echo no_fromreset > /root/nodeconfigured
			systemctl start target
			targetcli clearconfig confirm=True	
			targetcli saveconfig 
			/TopStor/resetdocker.sh	
			nmcli conn up clusterstub 
			nmcli conn delete mynode 
			nmcli conn delete mycluster 
			hostname localhost
			echo localhost > /etc/hostname
		fi
		echo $cmdline | egrep 'reboot|reset'
		if [ $? -eq 0 ];
		then
			reboot
		fi
		echo $cmdline | grep 'stop'
		if [ $? -eq 0 ];
		then
			echo hihihihihi
			exit
		fi
	fi
	echo $cmdline | grep restart 
	if [ $? -ne 0 ];
	then
		eth1=$1
	fi
fi
if [ $# -ge 2 ];
then
	eth2=$1
fi

mynodedev=$eth1
myclusterdev=$eth1
data1dev=$eth2
data2dev=$eth2
setenforce 0
aliast='alias'
targetcli clearconfig confirm=true
#nmcli conn delete clusterstub 
#nmcli conn delete mynode 
#nmcli conn delete mycluster 
nmcli conn up mynode
nmcli conn delete cmynode
nmcli conn delete cmycluster
isinitn='S'`cat /root/nodeconfigured`
echo $isinitn | grep 'Syes'
if [ $? -ne 0 ];
then
	#mynode='10.11.11.244/24'
	isconf='no'
	ipaddr=`cat /root/newipaddr`
 	ipaddrn=`echo 'S'$ipaddr | wc -c`
	if [ $ipaddrn -ge 5 ];
	then
		mynode=$ipaddr
	else
		x=$(( ( RANDOM % 40 )  + 3 ))
		mynode='10.11.11.'$x'/24'
	fi
	nmcli conn delete mynode
	nmcli conn add con-name mynode type ethernet ifname $mynodedev ip4 $mynode
	nmcli conn delete clusterstub
	nmcli conn add con-name clusterstub type ethernet ifname $myclusterdev ip4 169.168.12.12 
	#nmcli conn up clusterstub 


	ping -w 3 10.11.11.250
	if [ $? -ne 0 ];
	then
		mycluster='10.11.11.250/24'
		isconf_prim='noyes'
		isprimary=1
		echo the ping didn\'t find the initial cluster 250 so I am primary
	else
		mycluster=$mynode
		isconf_prim='nono'
		isprimary=0
		echo the ping found the initial cluster so I will not be primary
	fi
	nmcli conn delete mycluster
	nmcli conn add con-name mycluster type ethernet ifname $myclusterdev ip4 $mycluster
else
	isconf='yes'
	ipaddr=`cat /root/newipaddr`
 	ipaddrn=`echo 'S'$ipaddr | wc -c`
	if [ $ipaddrn -ge 5 ];
	then
		mynode=$ipaddr
		nmcli conn mod mynode ipv4.addresses $ipaddr
		nmcli conn up mynode 
	
	else
		mynode=`nmcli conn show mynode | grep ipv4.addresses | awk '{print $2}'`
	fi

	caddr=`cat /root/newcaddr`
 	caddrn=`echo 'S'$caddr | wc -c`
	if [ $caddrn -ge 5 ];
	then
		mycluster=$caddr
		nmcli conn mod mycluster ipv4.addresses $caddr
	else
		mycluster=`nmcli conn show mycluster | grep ipv4.addresses | awk '{print $2}'`
	fi
	myclusterip=`echo $mycluster | awk -F'/' '{print $1}'`
	mynodeip=`echo $mynode | awk -F'/' '{print $1}'`
# wait till the port is up
	ping -w 3 $mynodeip
      	while [ $? -ne 0 ];
	do
		sleep 1
		ping -w 3 $mynodeip
	done
# now the port should be up--- or other wise comment out all the above block and uncomment the below sleep
	#sleep 20
	
	isconf_prim='yesno'
	isprimary=0
	ping -w 3 $myclusterip 
	counter=`echo $RANDOM | cut -c -1`
	counter=$((counter+5))
	while [ $counter -ne 0 ];
	do
		echo counter=$counter
		ping -w 1 $myclusterip 
		if [ $? -eq 0 ];
		then
			counter=0
		else
			counter=$((counter-1))
			if [ $counter -eq 0 ];
			then
				isconf_prim='yesyes'
				isprimary=1
			fi
		fi
	done		
fi
myclusterip=`echo $mycluster | awk -F'/' '{print $1}'`
mynodeip=`echo $mynode | awk -F'/' '{print $1}'`
myip=$mynodeip
echo $mynodedev | grep $myclusterdev
if [ $? -eq 0 ];
then
	case $isconf_prim in 
		nono)
		;;
		noyes)
		;;
		yesno)
		;;
		yesyes)
		;;
	esac
	if [ $isprimary -ne 0 ];
	then
		echo I am prmary
		nmcli conn delete cmynode 
		echo nmcli conn add con-name cmynode type ethernet ifname $mynodedev ip4 $mynode ip4 $mycluster
		nmcli conn add con-name cmynode type ethernet ifname $mynodedev ip4 $mynode ip4 $mycluster
	else
		echo I am a cluster node 
		nmcli conn delete cmynode 
		nmcli conn add con-name cmynode type ethernet ifname $mynodedev ip4 $mynode
	fi
else
	case $isconf_prim in 
		nono)
		;;
		noyes)
		;;
		yesno)
		;;
		yesyes)
		;;
	esac
	nmcli conn add con-name cmynode type ethernet ifname $mynodedev ip4 $mynode
	nmcli conn add con-name cmycluster type ethernet ifname $myclusterdev ip4 $mycluster
	if [ $isprimary -ne 0 ];
	then
		nmcli conn up cmycluster
	fi

fi
echo adding cmynode
nmcli conn up cmynode
if [[ $isconf == 'yes' ]];
then
	echo strting target
	systemctl start target
	echo starting iscsid
	systemctl start iscsid 
fi
echo starting docker
systemctl start docker
rm -rf /root/newipaddr
rm -rf /root/newcaddr
echo starting intdns
docker run --rm --name intdns --hostname intdns --net bridge0 -e DNS_DOMAIN=qs.dom -e DNS_IP=10.11.12.7 -e LOG_QUERIES=true -itd --ip 10.11.12.7 -v /etc/localtime:/etc/localtime:ro -v /root/gitrepo/dnshosts:/etc/hosts moataznegm/quickstor:dns

docker run -d --name wetty   --rm -p $mynodeip:3000:3000 wettyoss/wetty --ssh-host=$mynodeip --ssh-user=root --base=/
leaderip=$myclusterip
if [ $isprimary -eq 1 ];
then
	etcd=$myclusterip
	leader=$myhost
else
	etcd=$mynodeip
	leader=`/pace/etcdget.py $myclusterip leader`
fi

echo nameserver 10.11.12.7 >  /root/gitrepo/resolv.conf
echo starting etcd 
docker run -itd --rm --name etcd --hostname etcd -v /etc/localtime:/etc/localtime:ro -v /root/gitrepo/resolv.conf:/etc/resolv.conf -p $etcd:2379:2379 -v /TopStor/:/TopStor -v /root/etcddata:/default.etcd --net bridge0 moataznegm/quickstor:etcd

echo starting etcdclient 
docker run -itd --rm --name etcdclient --hostname etcdclient -v /etc/localtime:/etc/localtime:ro -v /root/gitrepo/resolv.conf:/etc/resolv.conf --net bridge0 -v /TopStor/:/TopStor -v /pace/:/pace moataznegm/quickstor:etcdclient 
if [[ $isconf_prim == 'nono' ]];
then
 /pace/watchdoginit & disown
 /pace/keepsendingprim & disown
 exit
fi
if [[ $isconf_prim == 'noyes' ]];
then
 /pace/watchdogprim & disown
 /pace/watchdoginit & disown
 /pace/keepsendingprim & disown
fi

echo /TopStor/setipports.sh $myclusterip $leader $myhost sync
/TopStor/setipports.sh $myclusterip $leader $myhost sync




echo starting intstub 
docker run -itd --rm --privileged \
  -v /TopStor/smb.conf:/etc/samba/smb.conf:rw \
  -v /etc/:/hostetc/   \
  -v /root/gitrepo/resolv.conf:/etc/resolv.conf \
  -v /var/lib/samba/private:/var/lib/samba/private:rw \
  -v /TopStor/smbuser.sh:/root/smbuser.sh \
  --net bridge0 \
  --name intsmb --hostname intsmb moataznegm/quickstor:smb
 docker exec intsmb sh /hostetc/VolumeCIFSupdate.sh
#docker run -d --rm --name rmq --hostname rmq  -v /root/gitrepo/resolv.conf:/etc/resolv.conf --net bridge0 -p $etcd:5672:5672 -v /TopStor/:/TopStor -v /pace/:/pace moataznegm/quickstor:rabbitmq 
echo starting rabbitmq 
systemctl start rabbitmq-server
rabbitmqctl add_user rabb_Mezo YousefNadody 2>/dev/null
rabbitmqctl set_permissions -p / rabb_Mezo ".*" ".*" ".*" 2>/dev/null
started=0
while [ $started -eq 0 ];
do
		echo waiting etcd to settle 
		docker logs etcd | grep 'successfully notified init daemon' 
		if [ $? -eq 0 ];
	 	then
			started=1
	 	else
		 	sleep 1
	 	fi
done
echo starting > /root/dockerlogs.txt
checkcluster='0'
echo hihi$checkcluster | grep $myclusterip
while [ $? -ne 0 ];
do
	sleep 1
	docker exec etcdclient /pace/etcdputlocal.py clusternodeip $mynodeip
	docker exec etcdclient /pace/etcdputlocal.py clusternode $myhost
	if [ $isprimary -eq 1 ];
	then
		echo initializing etcd params 
		echo docker exec etcdclient /pace/etcdput.py $myclusterip clusternode $myhost
		echo isprimary $isprimary >> /root/dockerlogs.txt
		/TopStor/etcdput.py $myclusterip ActivePartners/$myhost $mynodeip 
		/TopStor/etcdput.py $myclusterip leaderip $myclusterip 
		echo docker exec  etcdclient /TopStor/etcdput.py $myclusterip leaderip $myclusterip >> /root/dockerlogs.txt
		/TopStor/etcdput.py $myclusterip leader $myhost 
		/TopStor/etcdput.py $myclusterip nextlead/er 'None' 
		etcdip=$myculsterip

	else
		echo waiting for me to join the cluster 
		echo isprimaryin0 $isprimary >> /root/dockerlogs.txt
		/pace/etcdget.py $myclusterip Active --prefix | grep $myhost
		if [ $? -ne 0 ];
		then
			/TopStor/etcdput.py $myclusterip possible/$myhost $mynodeip 
			echo I joined the cluster
		fi
		stillpossible=1
		while [ $stillpossible -eq 1 ];
		do
			/TopStor/etcdget.py possible --prefix | grep $myhost
			if [ $? -ne 0 ];
			then
				stillpossible=0
			else
				sleep 2
				echo waiting for me to join the cluster 
			fi
		done
		etcdip=$mynodeip
		stamp=`date +%s%N`
	fi
	echo initializaing volume pool leader clsuternode data
	myalias=`docker exec etcdclient /pace/etcdgetlocal.py $aliast/$myhost`
	leader=`/pace/etcdget.py $myclusterip leader`
	docker exec etcdclient /pace/etcdputlocal.py leader $leader 
	docker exec etcdclient /pace/etcdputlocal.py leaderip $myclusterip
	docker exec etcdclient /pace/etcdputlocal.py clusternode $myhost
	docker exec etcdclient /pace/etcddellocal.py sync/Snapperiod/initial $myhost request/$myhost 2>/dev/null
        docker exec etcdclient /pace/etcddellocal.py pool --prefix 2>/dev/null
	docker exec etcdclient /pace/etcddellocal.py volume --prefix 2>/dev/null
	docker exec etcdclient /pace/etcddellocal.py sync/pool Add_ 2>/dev/null
	docker exec etcdclient /pace/etcddellocal.py sync/pool Del_ 2>/dev/null
	docker exec etcdclient /pace/etcddellocal.py sync/volume Add_ 2>/dev/null
	docker exec etcdclient /pace/etcddellocal.py sync/volume Del_ 2>/dev/null
        /pace/etcdput.py $myclusterip $aliast/$myhost $myalias
	#/TopStor/syncq.py $myclusterip $myhost 2>/root/syncqerror
	stamp=`date +%s%N`
	myalias=`echo $myalias | sed 's/\_/\:\:\:/g'`
	/pace/etcddel.py $myclusterip sync/$aliast/Add_${myhost} --prefix
	if [ $isprimary -ne 0 ];
	then
 		/pace/etcddel.py $myclusterip ready --prefix
 		/pace/etcddel.py $myclusterip sync/ready/Add --prefix
	else
 		/pace/etcddel.py $mynodeip ready --prefix
		/TopStor/activepoolsync.py
	
	fi		
	/pace/etcdput.py $myclusterip sync/$aliast/Add_${myhost}_$myalias/request ${aliast}_$stamp.
	/pace/etcdput.py $myclusterip sync/$aliast/Add_${myhost}_$myalias/request/$myhost ${aliast}_$stamp.
	/pace/etcdput.py $myclusterip sync/$aliast/Add_${myhost}_$myalias/request/$leader ${aliast}_$stamp.
	issync=`/pace/etcdget.py $myclusterip sync initial`initial
	echo $issync | grep $myhost
	if [ $? -eq 0 ];
	then
		echo syncrequests only
		echo row 262 checksync init >> /root/checksync
    		/pace/checksyncs.py syncrequest $myclusterip $myhost $myip
       	else
		echo have to syncall
		echo row 266 checksync init >> /root/checksync
		/pace/checksyncs.py syncall $myclusterip $myhost $myip
	fi
	checkcluster=`docker exec etcdclient /TopStor/etcdgetlocal.py leaderip`
	echo $checkcluster >> /root/dockerlogs.txt
	echo hihi$checkcluster | grep $myclusterip
done
#############################3
/TopStor/etcddel.py $etcd pools --prefix 
/TopStor/etcddel.py $etcd sync/pools --prefix 
/TopStor/etcddel.py $etcd volume --prefix 
/TopStor/etcddel.py $etcd sync/volume --prefix 
/TopStor/etcdput.py $etcd mynodeip $mynodeip 
/TopStor/etcdput.py $etcd mynode $myhost 
/TopStor/etcdput.py $etcd leaderip $myclusterip 
/TopStor/etcdput.py $etcd isprimary $isprimary 
/TopStor/putEthernetPorts.py $myclusterip $leader $myhost

isreset=`cat /root/nodestatus`
echo ${isreset}$isprimary | grep reset1
if [ $? -eq 0 ];
then
	echo initializing admin user
	docker exec etcdclient /TopStor/UnixsetUser.py $myclusterip `hostname` admin tmatem
	/TopStor/UnixAddGroup $etcd Everyone usersNoUser admin
	echo runningnode > /root/nodestatus
fi
#rm -rf /TopStor/key/adminfixed.gpg && cp /TopStor/factory/factoryadmin /TopStor/key/adminfixed.gpg
if [ $isprimary -eq 1 ];
then
	echo adding all sync inits as I am primary
	echo docker exec etcdclient /pace/checksyncs.py syncinit $etcd
	echo row 293 checksync init >> /root/checksync
	/pace/checksyncs.py syncinit $etcd $myhost
fi
# echo running rabbit receive daemon
# /TopStor/topstorrecvreply.py $etcd & disown
/TopStor/etcdput.py $etcd ready/$myhost $mynodeip 



#docker run --restart unless-stopped --name git -v /root/gitrepo:/usr/local/apache2/htdocs/ --hostname sgit -p 10.11.11.252:80:80 -v /root/gitrepo/httpd.conf:/usr/local/apache2/conf/httpd.conf -itd -v /root/gitrepo/resolv.conf:/etc/resolv.conf moataznegm/quickstor:git
templhttp='/TopStor/httpd_template.conf'
rm -rf /TopStordata/httpd.conf
cp /TopStor/httpd.conf /TopStordata/
shttpdf='/TopStordata/httpd.conf'
docker rm -f httpd
docker rm -f flask
rm -rf $httpdf
#if [ $isprimary -ne 0 ];
#then
#	cp $templhttp $shttpdf
#	sed -i "s/MYCLUSTERH/$myclusterip/g" $shttpdf
#	sed -i "s/MYCLUSTER/$myclusterip/g" $shttpdf
#	echo running httpd fowrarder as I am not primary
#	docker run --rm --name httpd --hostname shttpd --net bridge0 -v /etc/localtime:/etc/localtime:ro -v /root/gitrepo/resolv.conf:/etc/resolv.conf -p $myclusterip:19999:19999 -p $myclusterip:80:80 -p $myclusterip:443:443 -v $shttpdf:/usr/local/apache2/conf/httpd.conf -v /root/topstorwebetc:/usr/local/apache2/topstorwebetc -v /topstorweb:/usr/local/apache2/htdocs/ -itd moataznegm/quickstor:git
#	docker run -itd --rm --name flask --hostname apisrv -v /etc/localtime:/etc/localtime:ro -v /pace/:/pace -v /pacedata/:/pacedata/ -v /root/gitrepo/resolv.conf:/etc/resolv.conf --net bridge0 -p $myclusterip:5001:5001 -v /TopStor/:/TopStor -v /TopStordata/:/TopStordata moataznegm/quickstor:flask
#fi
/TopStor/ioperf.py $etcd $myhost
echo docker exec etcdclient /TopStor/etcdput.py $myclusterip ready/$myhost $mynodeip 
/TopStor/etcdput.py $myclusterip ready/$myhost $mynodeip 
/TopStor/etcdput.py $myclusterip ActivePartners/$myhost $mynodeip 
stamp=`date +%s%N`
/pace/etcddel.py $myclusterip sync/ready/Add_${myhost} --prefix
/pace/etcddel.py $myclusterip sync/ActivePartners/Add_${myhost} --prefix
/TopStor/etcdput.py $myclusterip sync/ready/Add_${myhost}_$mynodeip/request ready_$stamp
/TopStor/etcdput.py $myclusterip sync/ready/Add_${myhost}_$mynodeip/request/$leader ready_$stamp
/TopStor/etcdput.py $myclusterip sync/ActivePartners/Add_${myhost}_$mynodeip/request/$leader ready_$stamp
/TopStor/etcdput.py $myclusterip sync/ActivePartners/Add_${myhost}_$mynodeip/request ActivePartners_$stamp
echo running iscsi watchdog daemon
/TopStor/etcddel.py $myclusterip rebootme $myhost
if [ $isprimary -ne 0 ];
then
 /pace/etcddel.py $myclusterip sync/ready/Add_${myhost} --prefix
 /pace/etcddel.py $myclusterip pools --prefix
 /pace/etcddel.py $myclusterip hosts --prefix
 /pace/etcddel.py $myclusterip vol  --prefix
 /pace/etcddel.py $myclusterip list --prefix
else
 /TopStor/etcddel.py $etcd rebootme $myhost
 /TopStor/etcdput.py $myclusterip nextlead/er $myhost
 /TopStor/etcddel.py $myclusterip sync/nextlead/Add_er_ --prefix
 /TopStor/etcdput.py $myclusterip sync/nextlead/Add_er_${myhost}/request nextlead_$stamp
 /TopStor/etcdput.py $myclusterip sync/nextlead/Add_er_${myhost}/request/$leader nextlead_$stamp
fi
 /TopStor/etcddel.py $myclusterip sync/diskref --prefix
 /TopStor/etcdput.py $myclusterip sync/diskref/add_add_add______/request diskref_$stamp
 /pace/diskref.sh $leader $myclusterip $myhost $mynodeip
#if [ $isprimary -ne 0 ];
#then
	/pace/checksyncs.py restetcd $myclusterip $myhost 
	/pace/checksyncs.py syncrequest $myclusterip $myhost 
 	/TopStor/etcddel.py $myclusterip sync/diskref --prefix
 	/TopStor/etcdput.py $myclusterip sync/diskref/add_add_add______/request diskref_$stamp
#fi
 /TopStor/refreshdisown.sh & disown 
 /TopStor/etcdput.py $etcd refreshdisown/$myhost yes 
 #/pace/syncrequestlooper.sh $leaderip $myhost & disown
 /pace/rebootmeplslooper.sh $myclusterip $myhost & disown
 #/TopStor/receivereplylooper.sh & disown
 #/TopStor/iscsiwatchdoglooper.sh $mynodeip $myhost & disown 
 /pace/heartbeatlooper.sh & disown
 #/pace/updateconfiglooper.sh $myclusterip $myhost & disown
 stamp=`date +%s%N`
/TopStor/etcddel.py $myclusterip rebootwait/$myhost
/TopStor/etcddel.py $myclusterip sync/ready $myhost 
/TopStor/etcdput.py $myclusterip ready/$myhost $mynodeip
/TopStor/etcdput.py $mynodeip ready/$myhost $mynodeip
/pace/etcdsync.py $myclusterip $mynodeip ready ready
/pace/etcdsync.py $myclusterip $mynodeip Active Active 
/TopStor/etcdput.py $myclusterip sync/ready/Add_${myhost}_$mynodeip/request ready_$stamp 
/TopStor/etcdput.py $myclusterip sync/ready/Add_${myhost}_$mynodeip/request/$leader ready_$stamp 
#/pace/diskref.py $leader $myculsterip $myhost $mynodeip 
/pace/diskchange.sh add initial disk
rm -rf /promgraf/grafana.db
cp /TopStor/grafana.db /promgraf/
/TopStor/getcversion.sh $myclusterip $leader $myhost
if [ $isprimary -ne 0 ];
then
	cp $templhttp $shttpdf
	sed -i "s/MYCLUSTERH/$myclusterip/g" $shttpdf
	sed -i "s/MYCLUSTER/$myclusterip/g" $shttpdf
	echo running httpd fowrarder as I am not primary
	docker run --rm --name httpd --hostname shttpd --net bridge0 -v /etc/localtime:/etc/localtime:ro -v /root/gitrepo/resolv.conf:/etc/resolv.conf -p $myclusterip:19999:19999 -p $myclusterip:80:80 -p $myclusterip:443:443 -v $shttpdf:/usr/local/apache2/conf/httpd.conf -v /root/topstorwebetc:/usr/local/apache2/topstorwebetc -v /topstorweb:/usr/local/apache2/htdocs/ -itd moataznegm/quickstor:git
	docker run -itd --rm --name flask --hostname apisrv -v /etc/localtime:/etc/localtime:ro -v /pace/:/pace -v /pacedata/:/pacedata/ -v /root/gitrepo/resolv.conf:/etc/resolv.conf --net bridge0 -p $myclusterip:5001:5001 -v /TopStor/:/TopStor -v /TopStordata/:/TopStordata moataznegm/quickstor:flask3
	/TopStor/promserver.sh $myclusterip 
fi
mydns=`/TopStor/etcdget.py $myclusterip dnsname/$myhost`
#nmcli conn modify cmynode ipv4.dns ''
nmcli conn modify cmynode ipv4.dns $mydns
nmcli conn up cmynode
docker rm -f promexport
docker run -d -p $mynodeip:9100:9100 -v /proc:/proc -v /sys:/sys --name promexport prom/node-exporter
docker rm -f promcadvisor
docker run   --volume=/:/rootfs:ro   --volume=/var/run:/var/run:ro   --volume=/sys:/sys:ro   --volume=/var/lib/docker/:/var/lib/docker:ro   --volume=/dev/disk/:/dev/disk:ro   --publish=$mynodeip:9101:8080   --detach=true   --name=promcadvisor   --privileged   --device=/dev/kmsg   gcr.io/cadvisor/cadvisor
 #/pace/zfsping.py $leaderip $myhost & disown #### it is in refreshdisown
 /pace/fapilooper.sh & disown
