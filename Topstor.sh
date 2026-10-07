#!/bin/sh
export ETCDCTL_API=3
ETCDCTL_API=3
cd /TopStor
rm /tmp2/msgfile 2>/dev/null
mkdir /tmp2 &>/dev/null
chown apache /tmp2 &>/dev/null
mkfifo -m 660 /tmp2/msgfile 2>/dev/null

export REMOTE=Topstor
export ETCDCTL_API=3
#chgrp root /tmp/msgfile; 
chown apache /tmp2/msgfile; 
echo $$ > /var/run/topstor.pid
ClearExit() {
	echo got a signal > /TopStor/txt/sigstatus.txt
	rm /tmp2/msgfile
	rm /var/run/topstor.pid 
	exit 0;
}
trap ClearExit HUP
/TopStor/wpa
hostname=`hostname -s`
systemctl disable NetworkManager &>/dev/null
systemctl stop NetworkManager &>/dev/null
#/TopStor/autoGenPatch
pgrep beam 
while [ $? -ne 0 ];
do
 sleep 1
 pgrep beam
done
pgrep etcd
while [ $? -ne 0 ];
do
 sleep 1
 pgrep etcd
done
while true; do 
{
read line < /tmp2/msgfile
echo $line > /TopStordata/tmpline
request=`echo $line | awk '{print $1}'`
reqparam=`echo $line | awk '{$1="";print}'`
rm -rf /root/$request.txt 2>/dev/null
#./$request $reqparam >/dev/null 2>&1  & 
./$request $reqparam >/dev/null 2>/root/$request.txt  & 
}
done;
echo it is dead >/TopStor/txt/status.txt
