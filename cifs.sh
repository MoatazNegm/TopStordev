#!/bin/sh
cd /TopStor
export ETCDCTL_API=3
echo $@ > /root/cifsshtmp
resname=`echo $@ | awk '{print $1}'`
mounts=`echo $@ | awk '{print $2}' | sed 's/\-v/ \-v /g'`
ipaddr=`echo $@ | awk '{print $3}'`
ipsubnet=`echo $@ | awk '{print $4}'`
vtype=`echo $@ | awk '{print $5}'`
echo params $@ > /root/cifstmp
echo name $resname >> /root/cifstmp
echo mounts $mounts >> /root/cifstmp
echo ip and subnet $ipaddr $ipsubnet >> /root/cifstmp
docker rm -f $resname
nmcli conn mod cmynode -ipv4.addresses ${ipaddr}/$ipsubnet
nmcli conn mod cmynode +ipv4.addresses ${ipaddr}/$ipsubnet
nmcli conn up cmynode
echo $vtype | grep '_' 
if [ $? -ne 0 ];
then
		docker run -d $mounts --rm --privileged \
  		-e "HOSTIP=$ipaddr"  \
  		-p $ipaddr:135:135 \
  		-p $ipaddr:137:137/udp \
  		-p $ipaddr:138:138/udp \
  		-p $ipaddr:139:139 \
  		-p $ipaddr:445:445 \
  		-v /TopStordata/smb.${ipaddr}:/config/smb.conf:rw \
  		-v /TopStor/smb.conf:/etc/samba/smb.conf:rw \
  		-v /etc/:/hostetc/   \
  		-v /var/lib/samba/private:/var/lib/samba/private:rw \
  		--name $resname moataznegm/quickstor:smb
  		sleep 1 
  		docker exec $resname sh /hostetc/VolumeCIFSupdate.sh
else
	domain=`echo $@ | awk '{print $6}'`
	domainsrvn=`echo $@ | awk '{print $7}'`
	domainsrvi=`echo $@ | awk '{print $8}'`
	domadmin=`echo $@ | awk '{print $9}'`
	adminpass=`echo $@ | awk '{print $10}'`
 	wrkgrp=`echo $domain | awk -F'.' '{print $1}'`  
	membername=${wrkgrp}-$RANDOM
	cp /TopStor/smbmember.conf /etc/smbmember.conf_$membername
	sed -i "s/WRKGRP/$wrkgrp/g" /etc/smbmember.conf_$membername
	sed -i "s/DOMAINIP/$domainsrvi/g" /etc/smbmember.conf_$membername
	sed -i "s/DOMAIN/${domain^^}/g" /etc/smbmember.conf_$membername
  	cat /TopStordata/smb.${ipaddr} >> /etc/smbmember.conf_$membername
	echo nameserver $domainsrvi > /TopStordata/resolv_$wrkgrp
	#cp /TopStordata/smbmember.conf_$membername /etc/smbmember.conf_$membername
 	echo -e 'notyet=1 \nwhile [ $notyet -eq 1 ];\ndo\nsleep 3' > /etc/smb${membername}.sh
 	echo -e 'cat /etc/samba/smb.conf | grep' "'\[public\]'" >> /etc/smb${membername}.sh
 	echo -e 'if [ $? -eq 0 ];\nthen' >> /etc/smb${membername}.sh
 	echo -e ' cat /etc/samba/smb.conf | grep' "'\[private\]'" >> /etc/smb${membername}.sh
 	echo -e ' if [ $? -eq 0 ];\nthen' >> /etc/smb${membername}.sh
 	echo -e '  cat /etc/samba/smb.conf | grep' "'\[home\]'" >> /etc/smb${membername}.sh
 	echo -e '  if [ $? -eq 0 ];\nthen\nnotyet=0\nsleep 10\nfi\nfi\nfi\ndone' >> /etc/smb${membername}.sh
	echo -e "cat /hostetc/smbmember.conf_$membername > /etc/samba/smb.conf" >> /etc/smb${membername}.sh
 	echo  "service samba --full-restart"  >> /etc/smb${membername}.sh
 	chmod +w /etc/smb${membername}.sh
	myhost=`hostname`	
    	myclusterip=`docker exec etcdclient /TopStor/etcdgetlocal.py leaderip`
	echo myhost=$myhost myclusterip=$myclusterip
	mydns=`/TopStor/etcdget.py $myclusterip dnsname/$myhost`
	echo ll$mydns | grep '\.' 
	if [ $? -eq 0 ];
	then
		echo iamhere
		nmcli conn modify cmynode ipv4.dns $domainsrvi,$mydns
		echo nmcli conn modify cmynode ipv4.dns $domainsrvi,$mydns
	else
		echo no dns
		nmcli conn modify cmynode ipv4.dns $domainsrvi
		echo nmcli conn modify cmynode ipv4.dns $domainsrvi
	fi
	nmcli conn up cmynode
 	sync
 	adminpass=`echo $adminpass | sed 's/\@\@sep/\//g'`
 	adminpass=`/TopStor/decthis.sh $domain $adminpass | awk -F'_result' '{print $2}' `
 	docker run -d  $mounts --privileged --rm --add-host "${membername}.$domain ${membername}":$ipaddr  \
  		--hostname ${membername} \
  		-v /etc/localtime:/etc/localtime:ro \
  		-v /etc/:/hostetc/   \
  		-v /TopStordata/smb.${ipaddr}:/etc/smb.conf:rw \
		-v /TopStordata/resolv_$wrkgrp:/etc/resolv.conf \
  		-e DOMAIN_NAME=$domain \
  		-e ADMIN_SERVER=$domainsrvi \
  		-e WORKGROUP=$wrkgrp  \
  		-e AD_USERNAME=$domadmin \
  		-e AD_PASSWORD=$adminpass \
  		-p $ipaddr:137:137/udp \
  		-p $ipaddr:138:138/udp \
  		-p $ipaddr:139:139/tcp \
  		-p $ipaddr:445:445/tcp \
  		--name $resname moataznegm/quickstor:membersmb 
	#cat /TopStordata/resolv.conf > /etc/resolv.conf
	echo /TopStor/dockmember.sh $resname sh /hostetc/smb${membername}.sh 
	/TopStor/dockmember.sh $resname sh /hostetc/smb${membername}.sh

fi
