#!/usr/local/bin/zsh
cd /TopStor
echo 10.3.2.8 welcome | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -N  10.3.2.7 2234
read line < /tmp/msgrack ;
echo line=$line;
