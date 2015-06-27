#!/usr/local/bin/zsh
cd /TopStor
so=`echo $@ | awk '{print $1}'`;
dst=`echo $@ | awk '{print $2}'`;
passphrase=`echo $@ | awk '{print $3}'`;
pp=`echo $@ | awk '{print $4}'`;
porplus=$((pp+1));
ppzfs=$((pp+2));
proxyser=`cat proxy.txt | awk '{print $1}'`;
license=` cat proxy.txt | awk '{print $2}'`;
lineflag="failed"
while true; do
 issocat=`ps -auxw | grep -w socat | grep -w "$pp" | wc -c `;
 if [[ $issocat -le 3 ]]; 
 then
  stamp=`date +%s`
  read -t 2  line</tmp/msgrack ;
  echo initporxyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy >> txt/tmpproxyrequest
  echo $so $stamp $dst $license ProxysendReInit.sh $so $pp $passphrase $dst  | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -N $proxyser 2234

  echo $so $stamp $dst $license ProxysendReInit.sh $so $pp $passphrase $dst >> tmpl 
  sleep 2
  echo /usr/local/bin/socat -u TCP4:$proxyser:$pp,forever,reuseaddr PIPE:txt/cin$pp >>txt/tmpproxyrequest 
  /usr/local/bin/socat   PIPE:txt/cin$pp  TCP4:$proxyser:$pp,forever,reuseaddr &
 fi
 porplusin=`ps -auxw | grep -w socat | grep -w $porplus | wc -c`;
 porplusinn=$((porplusin+0));
 if [[ $porplusinn -le 3 ]]; 
 then
  echo $so $stamp $dst $license $msg  | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -N $proxyser 2234
 sleep 2
  echo initporxyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy >> txt/tmpproxyrequest
   echo /usr/local/bin/socat  TCP4:$proxyser:$porplus,forever,reuseaddr PIPE:txt/cout$pp >> txt/tmpproxyrequest 
   /usr/local/bin/socat  TCP4:$proxyser:$porplus,forever,reuseaddr PIPE:txt/cout$pp &
 fi;
done
