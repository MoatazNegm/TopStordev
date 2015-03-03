#!/usr/local/bin/zsh
cd /TopStor
so=`echo $@ | awk '{print $1}'`;
dst=`echo $@ | awk '{print $2}'`;
msg=`echo $@ | awk '{$1=$2=""; print}'`
echo $so $msg | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -N  $dst  2234
read -t 20 line < /tmp/msgrack ;
echo line=$line;
