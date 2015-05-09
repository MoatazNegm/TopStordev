#! /usr/local/bin/zsh
logging='/usr/local/www/apache24/data/des19/Data/currentinfo2.log'
cd /TopStor
Proxy=`echo $@ | awk '{print $1}'`;
pp=`echo $@ | awk '{print $2}'`;
ppplus=$((pp+1));
while true;  do  
 issocat=`ps -auxw | grep -w socat | grep "$ppplus" | wc -c `;
 if [[ $issocat -le 3 ]];
 then
  /usr/local/bin/socat TCP4:$Proxy:$ppplus,reuseaddr GOPEN:txt/cin$ppplus &
 sleep 1;
 fi
 issocat=`ps -auxw | grep -w socat | grep "$pp" | wc -c `;
 if [[ $issocat -le 3 ]];
 then
  /usr/local/bin/socat -u TCP4:$Proxy:$pp,reuseaddr GOPEN:txt/cout$pp &
 fi;
 sleep 4
done
