#!/usr/local/bin/zsh
cd /TopStor
so=`echo $@ | awk '{print $1}'`;
dst=`echo $@ | awk '{print $2}'`;
msg=`echo $@ | awk '{$1=$2=""; print}'`
lineflag="failed"
stamp=`date +%s`
flagcount=0;
while [[ $lineflag == "failed" && flagcount -le 5 ]]; do
{

echo $so $stamp $msg | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -N  $dst  2234
read -t 3 line < /tmp/msgrack ;
stampreply=`echo $line | awk '{print $1}'`;
flagcount=$((flagcount+1));
if [[ $stampreply == $stamp ]]; then lineflag=`echo $line | awk '{$1=""; print substr($0,2)}'`; fi 
}
done;
echo $lineflag
