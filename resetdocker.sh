myclusterf='/root/topstorwebetc/mycluster'
mynodef='/root/topstorwebetc/mynode'
mynodedev='enp0s8'
myclusterdev='enp0s8'
data1dev='enp0s8'
data2dev='enp0s8'

#hostname localhost
#echo localhost > /etc/hostname

pkill iscsiwatchdog
pkill zfsping 
pkill receive
pkill topstorrecvreply
pkill fapilooper
pkill syncrequestlooper
pkill checksyncs
pkill VolumeChecklooper
pkill VolumeCheck
pkill heartbeat
pkill refresh
pkill selects
pkill syncreq
pkill send
#zpool export -a
dockers=$(docker ps -q)
echo dockers=$dockers
for doc in $dockers;
do
	docker stop $doc
done

systemctl stop docker
pkill rebootme 
targetcli clearconfig confirm=True
systemctl stop rabbitmq-server
systemctl stop iscsid 
systemctl stop target 
#systemctl NetworkMnager restart
#nmcli conn delete mynode
#nmcli conn delete mycluster
