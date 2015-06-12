#! /usr/local/bin/zsh
logging='/usr/local/www/apache24/data/des19/Data/currentinfo2.log'
cd /TopStor
pp=`echo $@ | awk '{print $1}'`;
ppplus=$((pp+1));
oldstamp=0;
stamp=1;
pipefile="txt/cout"$pp

while [[ $e != "noproxy" ]]; do  
 readproxy="waiting";
 issocat=`ps -auxw | grep -w socat | grep "$pp" | wc -c `;
 if [[ $issocat -ge 3 ]];
 then
  echo start read  -r readproxy  txt/cout$pp >> txt/proxyinpp;
#   read -r readproxy < ${pipefile}f
#   echo "waiting" > ${pipefile}f;
  readproxy=`tail -n 1 txt/cout${pp}f `
  echo "-" > txt/cout${pp}f
  ee=` echo $readproxy | grep -v waiting | tail -n 1`
  een=` echo $ee | wc -c `;
  if [[ $een -ge 2 ]]; 
  then
   echo received $readproxy >> txt/proxyinpp
   line=$ee
   stamp=` echo $line | awk '{print $1}'`;
   e=` echo $line | awk '{$1=""; print substr($0,2)}'`;
   echo status: oldstamp=$oldstamp stamp=$stamp e=$e >> txt/proxyinpp
   if [[ $e == "ready" ]]; 
   then 
    if [[ $oldstamp != $stamp ]];
    then 
     echo this is a ready $e >> txt/proxyinpp
     oldstamp=$stamp;
     if [[ -p txt/cin$ppplus ]]; then echo $stamp ready > txt/cin$ppplus; 
      echo e=$e sendingready=$stamp ready  txt/cin$ppplus >> txt/proxyinpp;
     fi
    fi
   else
    if [[ $oldstamp != $stamp ]];
    then 
     oldstamp=$stamp;
     req=`echo $e | awk '{print $1}'`;
     par=`echo $e | awk '{$1="";print substr($0,2)}'`;
     echo running: $req $par  >> txt/proxyinpp ; 
     res=` ./$req $par `;
     echo run: $req $par  >> txt/proxyinpp ; 
     echo sending: $stamp $res  >> txt/proxyinpp ; 
     echo $stamp $res  > txt/cin$ppplus ; 
    else
     echo $stamp $res > txt/cin$ppplus
     echo resending: $stamp $res >> txt/proxyinpp
    fi 
   fi
  fi
 fi
done ;
task=`ps -aux | grep $pp | awk '{print $2}'`; 
kill -9 $task;
rm txt/in$pp;
datenow=`date +%m/%d/%Y`; timenow=`date +%T`;
logdata='Closing Session';
logthis=`./jsonthis3.sh Date $datenow time $timenow msg info user $partner data $logdata`;
oldlog=`cat $logging | sed 's/]//g'`; newlog=$oldlog,$logthis]; echo $newlog > $logging;
echo $datenow $timenow :$logdata > ${logging}2
#echo $pp;
