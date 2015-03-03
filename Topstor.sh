#!/usr/local/bin/zsh
cd /TopStor
mkfifo -m 660 /tmp/msgfile
mkfifo -m 660 /tmp/ackmsg;
mkfifo -m 600 /tmp/msgremotefile;
#./Topstorremote.sh &
chgrp moataz /tmp/msgfile; chgrp moataz /tmp/ackmsg;
chown www /tmp/msgfile; chown www /tmp/ackmsg
rm /TopStor/txt/*
ClearExit() {
	echo got a signal > /TopStor/txt/sigstatus.txt
	rm /tmp/msgfile
	rm /tmp/ackmsg;
	rm /tmp/msgremotefile;
	exit 0;
}
trap ClearExit HUP
while true; do 
{
read line < /tmp/msgfile
echo $line > /TopStor/tmpline
request=`echo $line | awk '{print $1}'`
reqparam=`echo $line | cut -d " " -f2-`
./$request $reqparam & 
}
done;
echo it is dead >/TopStor/txt/status.txt
