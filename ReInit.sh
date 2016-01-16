#!/usr/local/bin/zsh 
logging='/usr/local/www/apache24/data/des19/Data/currentinfo2.log'
pp=`echo $@ | awk '{print $1}'`;
task=`ps -aux | grep $pp | awk '{print $2}' | wc -c `;
taskn=$((task+0));
if [[ $taskn -le 2 ]];
then
 mkfifo txt/in$pp;
 mkfifo txt/out$pp;
 nc -lk $pp < txt/in$pp > txt/out$pp &
 echo waiting > txt/in$pp;
 ./ReClose.sh $pp &
 datenow=`date +%m/%d/%Y`; timenow=`date +%T`;
 logdata='Initializing_new_session';
 logthis=`./jsonthis3.sh Date $datenow time $timenow msg info user $partner data $logdata code Reinit@@@`;
 oldlog=`cat $logging | sed 's/]//g'`; newlog=$oldlog,$logthis]; echo $newlog > $logging;
 echo Reinit1000@$datenow@$timenow@. > ${logging}2
 #echo $pp;
 echo $pp;
else
 echo No$pp;
fi;
