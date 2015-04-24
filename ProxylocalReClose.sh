#! /usr/local/bin/zsh
logging='/usr/local/www/apache24/data/des19/Data/currentinfo2.log'
pp=`echo $@ | awk '{print $1}'`;
e="waiting";
echo entering while
while [[ $e != "done" ]]; do read -t 2 -r line; 
e="waiting"
 linen=`echo $line | wc -c `;
 if [[ $linen -ge 3 ]];
 then
  instamp=`echo $line | awk '{print $1}'`;
  e=`echo $line | awk '{$1=""; print substr($0,2)}'`;
  echo line=$line
  req=`echo $e | awk '{print $1}'`;
  par=`echo $e | awk '{$1="";print substr($0,2)}'`;
  if [[ $e != "waiting" ]]; 
  then 
   if [[ $e != "done" ]]; 
   then 
   ./$req $par > txt/inres$pp;
   rep=`cat txt/inres$pp`;
    echo echo $instamp ./$req $par
    sleep 10
   echo $instamp $rep  > txt/in$pp; else echo waiting  > txt/in$pp; fi
   echo $req $par >> txt/proxyinpp; 
  fi
 fi
done < txt/out$pp; 
datenow=`date +%m/%d/%Y`; timenow=`date +%T`;
logdata='Closing remote Session';
logthis=`./jsonthis3.sh Date $datenow time $timenow msg info user $partner data $logdata`;
oldlog=`cat $logging | sed 's/]//g'`; newlog=$oldlog,$logthis]; echo $newlog > $logging;
echo $datenow $timenow :$logdata > ${logging}2
#echo $pp;
