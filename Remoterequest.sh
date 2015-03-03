#!/usr/local/bin/zsh
cd /TopStor
so=`echo $@ | awk '{print $1}'`;
dst=`echo $@ | awk '{print $2}'`;

echo $so welcome | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -N  $dst  2234
read -t 20 line < /tmp/msgrack ;
echo line=$line;
