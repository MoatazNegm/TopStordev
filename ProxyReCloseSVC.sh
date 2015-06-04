#! /usr/local/bin/zsh
logging='/usr/local/www/apache24/data/des19/Data/currentinfo2.log'
cd /TopStor
Proxy=`echo $@ | awk '{print $1}'`;
pp=`echo $@ | awk '{print $2}'`;
ppplus=$((pp+1));
ppzfs=$((pp+2));
while true;  do  
 if [[ ! -p  txt/cin$ppplus ]];
 then
  /usr/local/bin/socat PIPE:txt/cin$ppplus TCP4:$Proxy:$ppplus &
  echo /usr/local/bin/socat PIPE:txt/cin$ppplus TCP4:$Proxy:$ppplus >> txt/tmpsocat

 fi
 if [[ ! -p txt/cout$pp ]];
 then
  /usr/local/bin/socat TCP4:$Proxy:$pp PIPE:txt/cout$pp &
  echo /usr/local/bin/socat  TCP4:$Proxy:$pp PIPE:txt/cout$pp >> txt/tmpsocat
 fi;
 if [[ ! -p txt/c$ppzfs ]];
 then
  /usr/local/bin/socat  TCP4:$Proxy:$ppzfs PIPE:txt/c$ppzfs &
  echo /usr/local/bin/socat  TCP4:$Proxy:$ppzfs PIPE:txt/c$ppzfs >> txt/tmpsocat
 fi;
 sleep 1
done
