#! /usr/local/bin/zsh
logging='/usr/local/www/apache24/data/des19/Data/currentinfo2.log'
cd /TopStor
Proxy=`echo $@ | awk '{print $1}'`;
pp=`echo $@ | awk '{print $2}'`;
ppplus=$((pp+1));
ppzfs=$((pp+2));
while true;  do  
 issocat=`ps -auxw | grep -w socat | grep -w "$ppplus" | wc -c `;
 if [[ $issocat -le 3 ]];
 then
  /usr/local/bin/socat PIPE:txt/cin$ppplus TCP4:$Proxy:$ppplus,forever,reuseaddr &
  echo /usr/local/bin/socat PIPE:txt/cin$ppplus TCP4:$Proxy:$ppplus,forever,reuseaddr >> txt/tmpsocat

 fi
 issocat=`ps -auxw | grep -w socat | grep -w "$pp" | wc -c `;
 if [[ $issocat -le 3 ]];
 then
  /usr/local/bin/socat TCP4:$Proxy:$pp,forever,reuseaddr PIPE:txt/cout$pp &
  echo /usr/local/bin/socat TCP4:$Proxy:$pp,forever,reuseaddr PIPE:txt/cout$pp >> txt/tmpsocat
 fi;
 issocat=`ps -auxw | grep -w socat | grep -w "$ppzfs" | wc -c `;
 if [[ $issocat -le 3 ]];
 then
  /usr/local/bin/socat TCP4:$Proxy:$ppzfs,forever,reuseaddr PIPE:txt/c$ppzfs &
  echo /usr/local/bin/socat  TCP4:$Proxy:$ppzfs,forever,reuseaddr PIPE:txt/c$ppzfs >> txt/tmpsocat
 fi;
 sleep 1
done
