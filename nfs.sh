#!/bin/sh
cd /TopStor
export ETCDCTL_API=3
echo $@ > /root/cifsshtmp
resname=`echo $@ | awk '{print $1}'`
mounts=`echo $@ | awk '{print $2}' | sed 's/\-v/ \-v /g'`
ipaddr=`echo $@ | awk '{print $3}'`
ipsubnet=`echo $@ | awk '{print $4}'`
vtype=`echo $@ | awk '{print $5}'`
echo $@ > /root/cifstmp
echo $resname >> /root/cifstmp
echo $mounts >> /root/cifstmp
echo $ipaddr $ipsubnet >> /root/cifstmp
docker rm -f $resname
nmcli conn mod cmynode -ipv4.addresses ${ipaddr}/$ipsubnet
nmcli conn up cmynode
nmcli conn mod cmynode +ipv4.addresses ${ipaddr}/$ipsubnet
nmcli conn up cmynode
echo docker run -d $mounts --rm --privileged -p $ipaddr:2049:2049 -p $ipaddr:2049:2049/udp /\ 
echo 	 	-p $ipaddr:111:111     -p $ipaddr:111:111/udp   \ 
echo  		-p $ipaddr:32765:32765 -p $ipaddr:32765:32765/udp \ 
echo   		-p $ipaddr:32767:32767 -p $ipaddr:32767:32767/udp \ 
echo 		-v /TopStordata/exportsip.${ipaddr}:/etc/exports:ro \ 
echo 		--name $resname \ 
echo   		erichough/nfs-server
docker run -d $mounts --rm --privileged -p $ipaddr:2049:2049 -p $ipaddr:2049:2049/udp -p $ipaddr:111:111 -p $ipaddr:111:111/udp -p $ipaddr:32765:32765 -p $ipaddr:32765:32765/udp -p $ipaddr:32767:32767 -p $ipaddr:32767:32767/udp -v /TopStordata/exportsip.${ipaddr}:/etc/exports:ro --name $resname erichough/nfs-server

#docker run  -v /pdhcp1287810983/nftt_2386812076:/pdhcp1287810983/nftt_2386812076:rw --rm --privileged --cap-add SYS_ADMIN -e HOSTIP=10.11.11.23 -p 10.11.11.23:2049:2049 -v /TopStordata/exportsip.10.11.11.23:/etc/exports:ro --name NFS-10.11.11.23 -e SHARED_DIRECTORY=/pdhcp1287810983/nftt_2386812076 -p 10.11.11.23:111:111 itsthenetwork/nfs-server-alpine
#docker run  -v /pdhcp1287810983/nftt_2386812076:/pdhcp1287810983/nftt_2386812076:rw --rm --privileged  -p 10.11.11.23:2049:2049 -v /TopStordata/exportsip.10.11.11.23:/etc/exports:ro --name NFS-10.11.11.23  -p 10.11.11.23:111:111 -p 10.11.11.23:23765:23765 -p 10.11.11.23:23766:23766 -p10.11.11.23:23767:23767  erichough/nfs-server
