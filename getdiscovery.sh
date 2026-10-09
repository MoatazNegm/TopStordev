#!/usr/bin/sh
[ -f /TopStor/flavor.sh ] && . /TopStor/flavor.sh
cd /TopStor/
echo hihi>/root/tmpgetdiscovery
etcd='10.11.11.253'
/TopStor/etcddel.py $etcd possible --prefix
leaderip=`docker exec etcdclient /TopStor/etcdgetlocal.py leaderip`
/TopStor/etcddel.py $leaderip possible --prefix
# The scan below runs until it is told to stop (or 600 rounds).  It is started through the node's command queue
# (topstorrecvreply.py runs one command at a time), so in the foreground it held every later command -- adding a
# user, for one -- until the scan ended.  The script therefore starts itself again detached and returns at once.
if [ -z "$GETDISCOVERY_BG" ]; then
	for pid in $(pidof -x getdiscovery.sh); do
	    if [ $pid != $$ ]; then
	        echo "[$(date)] : discovery.sh : Process is already running with PID $pid"
	        exit 1
	    fi
	done
	GETDISCOVERY_BG=1 setsid nohup /TopStor/getdiscovery.sh "$@" >/dev/null 2>&1 </dev/null &
	exit 0
fi
cd /TopStor
# the discovery etcd database is kept between scans (tojoin / ackjoin must survive a new scan);
# stale possible/ keys are deleted explicitly above and tostop is reset below
mkdir -p /TopStordata/discovery

node_device=`nmcli -g connection.interface-name connection show cmynode | head -n 1`
if [ -z "$node_device" ]; then
	echo "cmynode has no active device"
	exit 1
fi
nmcli connection modify cmynode +ipv4.addresses $etcd/24
nmcli device reapply $node_device
rm -rf /TopStordata/discovery.sh
cp /TopStor/discovery.sh /TopStordata/
sed -i 's/SLEEP/sleep 10/g' /TopStordata/discovery.sh
leaderip=`docker exec etcdclient /TopStor/etcdgetlocal.py leaderip`
echo starting etcd 
docker run  --rm --name discovery --hostname discovery -v /etc/localtime:/etc/localtime:ro -v /root/gitrepo/resolv.conf:/etc/resolv.conf -p $etcd:2379:2379 -v /TopStor/:/TopStor -v /TopStordata/discovery:/default.etcd -v /TopStordata/discovery.sh:/runme.sh --net ${DOCKER_NET:-bridge0} moataznegm/quickstor:etcd  &
# the container registers in the internal DNS some seconds after it starts, longer when the node is busy (a second node
# booting): a lookup after a fixed 3 s found nothing, discovery.sh got etcdip='' , the discovery etcd never ran and the scan
# below polled a dead port for its 600 rounds while the joining node announced itself to nobody.  Wait for the answer.
newip=
for tries in `seq 1 60`
do
	newip=`docker exec intdns nslookup discovery | grep Address | grep -v 127 | awk '{print $2}'`
	[ -n "$newip" ] && break
	sleep 1
done
echo newip=$newip
if [ -z "$newip" ]; then
	echo "discovery container did not get an address in the internal DNS after 60 s, scan not started"
	docker rm -f discovery
	nmcli connection modify cmynode -ipv4.addresses $etcd/24
	nmcli device reapply $node_device 2>/dev/null
	exit 1
fi
docker rm -f discovery
rm -rf /TopStordata/discovery.sh
cp /TopStor/discovery.sh /TopStordata/
sed -i 's/SLEEP//g' /TopStordata/discovery.sh
sed -i "s/ETCDIP/$newip/g" /TopStordata/discovery.sh
docker run  -itd --rm --name discovery --hostname discovery -v /etc/localtime:/etc/localtime:ro -v /root/gitrepo/resolv.conf:/etc/resolv.conf -p $etcd:2379:2379 -v /TopStor/:/TopStor -v /TopStordata/discovery:/default.etcd -v /TopStordata/discovery.sh:/runme.sh --net ${DOCKER_NET:-bridge0} moataznegm/quickstor:etcd
counter=0
# the discovery database is kept between scans, so tostop still says yes from the last one: reset it
# and make sure etcd (just started) took it, or the loop below would stop at once
for tries in `seq 1 30`
do
	./etcdput.py $etcd tostop no >/dev/null
	[ "`/TopStor/etcdget.py $etcd tostop`" = "no" ] && break
	sleep 1
done
/TopStor/etcddel.py $etcd possible --prefix
/TopStor/etcddel.py $leaderip  possible --prefix
while true
do
	if [ -z "`docker ps -q -f name=^discovery$`" ]; then
		echo "discovery container is not running, scan stopped"
		break
	fi
	lines=`/TopStor/etcdget.py $etcd possible --prefix`
	counter=$((counter+1))
	echo $lines
	lines=`/TopStor/etcdget.py $etcd tostop`'s'
	/TopStor/syncpossibles.py $leaderip $etcd
	echo $lines | grep yes
	if [ $? -eq 0 ];
	then
		break
	fi
	if [ $counter -ge 600  ];
	then
		break
	fi
	sleep 1 

done

./etcdput.py $etcd tostop yes 
docker rm -f discovery
nmcli connection modify cmynode -ipv4.addresses $etcd/24
nmcli device reapply $node_device 2>/dev/null

