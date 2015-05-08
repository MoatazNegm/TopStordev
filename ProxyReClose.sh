#! /usr/local/bin/zsh
logging='/usr/local/www/apache24/data/des19/Data/currentinfo2.log'
cd /TopStor
Proxy=`echo $@ | awk '{print $1}'`;
pp=`echo $@ | awk '{print $2}'`;
ppplus=$((pp+1));
oldstamp=0;
while [[ $e != "done" ]]; do  
 readproxy="";
 issocat=`ps -auxw | grep -w socat | grep "$pp" | wc -c `;
 if [[ $issocat -ge 3 ]];
 then
  read  readproxy < txt/cout$pp
 fi
 ee=` echo $readproxy | grep -v waiting | tail -n 1`
 een=` echo $ee | wc -c `;
 echo $ee
 if [[ $een -ge 2 ]]; 
 then
  line=$ee
  stamp=` echo $line | awk '{print $1}'`;
  e=` echo $line | awk '{$1=""; print substr($0,2)}'`;
  echo status: stamp=$stamp e=$e >> txt/proxyinpp
  if [[ $e == "ready" ]]; 
  then 
    echo $stamp ready > txt/cin$pp;
    echo e=$e sendingready=$stamp ready >> txt/proxyinpp;
  else
   if [[ $oldstamp != $stamp ]];
   then 
    oldstamp=$stamp;
    req=`echo $e | awk '{print $1}'`;
    par=`echo $e | awk '{$1="";print substr($0,2)}'`;
    res=` ./$req $par `;
    echo $stamp $res  >> txt/proxyinpp ; 
    echo $stamp $res  > txt/cin$pp ; 
   else
    echo $stamp $res > txt/cin$pp;
   fi 
  fi
 fi
 sleep 5;
done;
task=`ps -aux | grep $pp | awk '{print $2}'`; 
kill -9 $task;
rm txt/in$pp;
datenow=`date +%m/%d/%Y`; timenow=`date +%T`;
logdata='Closing Session';
logthis=`./jsonthis3.sh Date $datenow time $timenow msg info user $partner data $logdata`;
oldlog=`cat $logging | sed 's/]//g'`; newlog=$oldlog,$logthis]; echo $newlog > $logging;
echo $datenow $timenow :$logdata > ${logging}2
#echo $pp;
