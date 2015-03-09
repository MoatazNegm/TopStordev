#!/usr/local/bin/zsh
cd /TopStor
ClearExit() {
	echo got a signal > /TopStor/txt/sigstatusremote.txt
	kill -9 `ps -ef | grep nc  | awk '{print $1}'`
	exit 0;
}
trap ClearExit HUP
while true; do 
{
nc -l 2234 | gunzip | openssl enc -d -aes-256-cbc -a -A -k SuperSecretPWD > /tmp/msgremotefile & 
read line < /tmp/msgremotefile;
echo $line > /TopStor/tmplineremote
stamp=`echo $line | awk '{print $2}'`
request=`echo $line | awk '{print $1}'`
searsource=` cat partners.txt | grep "$reqeust"`; 
ispartner=`echo $searsource | wc -c `
#echo $line $searsource | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -N  $request 2235 & 
if [[ $searsource == $request ]]; then
stamp=`echo $line | awk '{print $2}'`;
reqparam=`echo $line | awk '{$1=$2=""; print substr($0,3) }'`;
echo $stamp Authorized $reqparam $searsource $request | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -N  $request 2235 ;
./dummy.sh $reqparam > /tmp/msgfile; 
echo $reqparam > msgfiletmp;
sleep 1;
#echo done | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -N  $request 2235 & ;
else
echo $stamp Not Authorized:$line | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -N  $request 2235 & ;
fi
}
done;
echo it is dead >/TopStor/txt/statusremote.txt
