#!/usr/local/bin/zsh
cd /TopStor
so=`echo $@ | awk '{print $1}'`;
dst=`echo $@ | awk '{print $2}'`;
reply=`echo $@ | awk '{print $3}'`;
msg=`echo $@ | awk '{$1=$2=$3=""; print substr($0,4)}'`
lineflag="failed"
stamp=`date +%s`
read -t 2  line < /tmp/msgrack ;
flagcount=0;
echo xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx >> txt/tmprequest
while [[ $lineflag == "failed" && flagcount -le 5 ]]; do
{
echo echo $so $stamp $reply $msg \| openssl enc -a -A -aes-256-cbc -k SuperSecretPWD \| gzip -cf \| nc -N  $dst  2234 >> txt/tmprequest
echo $so $stamp $reply $msg | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -N  $dst  2234
read -t 20 line < /tmp/msgrack ;
stampreply=`echo $line | awk '{print $1}'`;
flagcount=$((flagcount+1));
if [[ $stampreply == $stamp ]]; then echo line=$line >> txt/tmprequest; lineflag=`echo $line | awk '{$1=$2="";print substr($0,3)}'`;  fi 
echo loopline=$lineflag >> txt/tmprequest
}
done;
