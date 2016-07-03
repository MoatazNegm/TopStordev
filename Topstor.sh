#!/usr/local/bin/zsh
cd /TopStor
rm /tmp/msgfile 2>/dev/null
#rm /tmp/msgrack 2>/dev/null
#rm /tmp/msgremotefile 2>/dev/null
mkfifo -m 660 /tmp/msgfile 2>/dev/null
#mkfifo -m 600 /tmp/msgrack 2>/dev/null
#mkfifo -m 600 /tmp/msgremotefile 2>/dev/null
export REMOTE=Topstor
#./Topstorremote.sh &
#./Topstorremoteack.sh &
chgrp moataz /tmp/msgfile; 
chown apache /tmp/msgfile; 
echo $$ > /var/run/topstor.pid
#rm /TopStor/txt/*
ClearExit() {
	echo got a signal > /TopStor/txt/sigstatus.txt
	rm /tmp/msgfile
#	rm /tmp/msgrack;
#	rm /tmp/msgremotefile;
	rm /var/run/topstor.pid 
#	ps -aux | grep /bin/nc | kill -9
	exit 0;
}
trap ClearExit HUP
while true; do 
{
read line < /tmp/msgfile
echo $line > /TopStordata/tmpline
request=`echo $line | awk '{print $1}'`
#reqparam=`echo $line | cut -d " " -f2-`
reqparam=`echo $line | awk '{$1="";print}'`

./$request $reqparam >/dev/null 2>&1  & 
}
done;
echo it is dead >/TopStor/txt/status.txt
