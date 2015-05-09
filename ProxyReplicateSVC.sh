#!/usr/local/bin/zsh
cd /TopStor
so=`echo $@ | awk '{print $1}'`;
dst=`echo $@ | awk '{print $2}'`;
pp=`echo $@ | awk '{print $5}'`;
porplus=$((pp+1));
msg=`echo $@ | awk '{$1=$2=""; print substr($0,3)}'`
proxyser=`cat proxy.txt | awk '{print $1}'`;
license=` cat proxy.txt | awk '{print $2}'`;
lineflag="failed"
mkfifo txt/cin$pp txt/cout$pp
while true; do
 issocat=`ps -auxw | grep -w socat | grep -w "$pp" | wc -c `;
 if [[ issocat -le 3 ]]; 
 then
  stamp=`date +%s`
  read -t 2  line</tmp/msgrack ;
  echo initporxyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy >> txt/tmpproxyrequest
  echo $so $stamp $dst $license $msg  | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -N $proxyser 2234
  echo echo $so $stamp $dst $license $msg  \| openssl enc -a -A -aes-256-cbc -k SuperSecretPWD \| gzip -cf \| nc -N $proxyser 2234 >> txt/tmpproxyrequest
  sleep 2
  echo /usr/local/bin/socat TCP4:$proxyser:$pp,reuseaddr GOPEN:txt/cin$pp >>txt/tmpproxyrequest 
#  echo /usr/local/bin/socat TCP4:$proxyser:$pp,reuseaddr GOPEN:txt/cin$pp 
  /usr/local/bin/socat TCP4:$proxyser:$pp,reuseaddr GOPEN:txt/cin$pp &
 fi
 porplusin=`ps -auxw | grep -w socat | grep -w $porplus | wc -c`;
 porplusinn=$((porplusin+0));
 if [[ $porplusinn -le 3 ]]; 
 then
  echo $so $stamp $dst $license $msg  | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -N $proxyser 2234
 sleep 2
   echo /usr/local/bin/socat -u TCP4:$proxyser:$porplus,reuseaddr GOPEN:txt/cout$pp 2>txt/socatit >> txt/tmpproxyrequest
# echo   /usr/local/bin/socat -u TCP4:$proxyser:$porplus,reuseaddr GOPEN:txt/cout$pp 
   /usr/local/bin/socat -u TCP4:$proxyser:$porplus,reuseaddr GOPEN:txt/cout$pp &
 fi;
done
