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
echo listening
nc -l 2234 | gunzip | openssl enc -d -aes-256-cbc -a -A -k SuperSecretPWD > /tmp/msgremotefile & 
read line < /tmp/msgremotefile;
echo newdata;
echo $line > /TopStor/tmplineremote
request=`echo $line | awk '{print $1}'`
searsource=` cat partners.txt | grep "$reqeust"`; 
ispartner=`echo $searsource | wc -c `
#echo $line $searsource | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -N  $request 2235 & 
if [[ $searsource == $request ]]; then
reqparam=`echo $line | cut -d " " -f2-`;
echo trusted ;
echo reqparam:$reqparam 
echo Authorized:$reqparam $searsource $request | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -N  $request 2235 
./pump.sh $reqparam ;
echo $reqparam > msgfiletmp
sleep 1;
#echo done | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -N  $request 2235 & ;
else
echo Not Authorized:$line | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -N  $request 2235 & ;
fi
}
done;
echo it is dead >/TopStor/txt/statusremote.txt
