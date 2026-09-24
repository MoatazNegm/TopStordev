#!/bin/sh
eth1='enp0s8'
eth2='enp0s8'
templhttp='/TopStor/httpd_template.conf'
shttpdf='/TopStordata/httpd_8080.conf'
myclusterip=`echo $@ | awk '{print $1}'`
req54=`echo $@ | awk '{print $2}'`
initip='10.11.11.254'
leaderip=`docker exec etcdclient /TopStor/etcdgetlocal.py leaderip`
docker rm -f httpd_local
rm -rf $shttpdf
cp $templhttp ${shttpdf}_local
sed -i "s/MYCLUSTER/$leaderip/g" ${shttpdf}_local
echo hihih${req54} | egrep 'yes|y' 
if [ $? -eq 0 ]; 
then
 	_8080=$initip
else
	_8080=`docker exec etcdclient /TopStor/etcdgetlocal.py mynodeip`
fi
docker run --rm --name httpd_local --hostname shttpd_local --net intdns-net -v /etc/localtime:/etc/localtime:ro -v /root/gitrepo/resolv.conf:/etc/resolv.conf -p $_8080:8080:8080 -v ${shttpdf}_local:/usr/local/apache2/conf/httpd.conf -v /root/topstorwebetc:/usr/local/apache2/topstorwebetc -v /topstorweb:/usr/local/apache2/htdocs/ -itd moataznegm/quickstor:git
