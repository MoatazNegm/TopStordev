#!/usr/local/bin/zsh
cd /TopStor
ClearExit() {
	echo got a signal > /TopStor/txt/sigstatusremote.txt
	exit 0;
}
trap ClearExit HUP
while true; do 
{
read line < /tmp/msgfiletmp
echo $line > /TopStor/tmplineremote
request=`echo $line | awk '{print $1}'`
searsource=` cat txt/partners.txt | grep "$reqeust"`; 
ispartner=`echo searsource | wc -c `
if [[ $ispartner -ge 3 ]]; then
reqparam=`echo $line | cut -d " " -f2-`;
echo $reqparam | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -N  $request 2235 & 
echo $reqparam > /tmp/msgfile;
echo done | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -N  $request 2235 & ;
else
echo Not Authorized:$line | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -N  $request 2235 & ;
fi
}
done;
echo it is dead >/TopStor/txt/statusremote.txt
