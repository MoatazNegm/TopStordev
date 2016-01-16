#!/usr/local/bin/zsh
logging='/usr/local/www/apache24/data/des19/Data/currentinfo2.log'
pp=`echo $@ | awk '{print $1}'`;
e="waiting";
while [[ $e != "done" ]]; do read -r line; 
e=` echo $line `;
 req=`echo $e | awk '{print $1}'`;
 par=`echo $e | awk '{$1="";print substr($0,2)}'`;
 if [[ $e != "waiting" ]]; then ./$req $par > txt/in$pp;
	echo $req $par >> txt/inpp; 
 fi
done < txt/out$pp; 
task=`ps -aux | grep $pp | awk '{print $2}'`; 
kill -9 $task;
rm txt/out$pp;
rm txt/in$pp;
datenow=`date +%m/%d/%Y`; timenow=`date +%T`;
logdata='Closing Session';
logthis=`./jsonthis3.sh Date $datenow time $timenow msg info user $partner data $logdata ReClose1000@@@.`;
oldlog=`cat $logging | sed 's/]//g'`; newlog=$oldlog,$logthis]; echo $newlog > $logging;
echo ReClose1000@$datenow@$timenow@. > ${logging}2
#echo $pp;
