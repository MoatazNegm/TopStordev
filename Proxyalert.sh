#!/usr/local/bin/zsh
cd /TopStor
so=`echo $@ | awk '{print $1}'`;
dst=`echo $@ | awk '{print $2}'`;
passphrase=`echo $@ | awk '{print $3}'`;
pp=`echo $@ | awk '{print $4}'`;
porplus=$((pp+1));
ppzfs=$((pp+2));
msg=`echo $@ | awk '{$1=$2=""; print substr($0,3)}'`
proxyser=`cat proxy.txt | awk '{print $1}'`;
license=` cat proxy.txt | awk '{print $2}'`;
lineflag="failed"
  stamp=`date +%s`
  read -t 2  line</tmp/msgrack ;
  echo initporxyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy >> txt/tmpproxyrequest
  echo $so $stamp $dst $license ProxysendReInit.sh $so $pp $passphrase  | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -N $proxyser 2234
#  echo echo $so $stamp $dst $license $msg  \| openssl enc -a -A -aes-256-cbc -k SuperSecretPWD \| gzip -cf \| nc -N $proxyser 2234 >> txt/tmpproxyrequest
sleep 2
