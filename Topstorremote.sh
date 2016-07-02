#!/usr/local/bin/zsh
cd /TopStor
partners='/TopStordata/partners.txt'
rm /tmp/msgremotefile 2>/dev/null
rm /tmp/msgrack 2>/dev/null
mkfifo -m 600 /tmp/msgremotefile 2>/dev/null
mkfifo -m 600 /tmp/msgrack 2>/dev/null
echo $$ > /var/run/topstorremote.pid
ClearExit() {
	echo got a signal > /TopStor/txt/sigstatusremote.txt
	rm /tmp/msgremotefile;
        rm /tmp/msgrack;
	rm /var/run/topstorremote.pid
	exit 0;
}
trap ClearExit HUP
#./ProxySVC.sh &
while true; do
{
nc -ld 2234 --ssl-cert /TopStor/key/TopStor.crt --ssl-key /TopStor/key/TopStor.key > /tmp/msgremotefile & 
read line < /tmp/msgremotefile;
echo $line > /TopStor/tmplineremote
stamp=`echo $line | awk '{print $2}'`
request=`echo $line | awk '{print $1}'`
searsource=` cat $partners | grep "$request" | awk '{print $1}'`; 
echo $request $searcsource > txt/tmpreq
ispartner=`echo $searsource | wc -c `
if [[ $searsource == $request ]]; then
stamp=`echo $line | awk '{print $2}'`;
reply=`echo $line | awk '{print $3}'`;
reqparam=`echo $line | awk '{$1=$2=$3=""; print substr($0,4) }'`;
instr=`echo $reqparam | awk '{print $1 }'`;
oper=`echo $reqparam | awk '{$1=""; print substr($0,2) }'`;
if [[ $reply == "rep" ]];
then 
res=`./$instr $oper`;
echo $stamp Authorized $res |  nc -w 5 --ssl-cert /TopStor/key/TopStor.crt --ssl-key /TopStor/key/TopStor.key $request 2235 ;
else
./$instr $oper;
echo $stamp Authorized received | nc -w 5 --ssl-cert /TopStor/key/TopStor.crt --ssl-key /TopStor/key/TopStor.key  $request 2235 ;
fi
echo $reqparam > msgfiletmp;
else
echo $stamp Not Authorized:$line | nc -w 5 --ssl-cert /TopStor/key/TopStor.crt --ssl-key /TopStor/key/TopStor.key $request 2235 & ;
fi
}
done;
echo it is dead >/TopStor/txt/statusremote.txt
