#! /bin/sh
logging='/usr/local/www/apache24/data/des19/Data/currentinfo2.log'
pool=`echo $@ | awk '{print $2 }'`;
partner=`echo $@ | awk '{print $3 }'`;
pp=` cat partners.txt | grep -w "$partner" | awk '{print $5}'`;
ppzfs=$((pp+2));
vol=`echo $@ | awk '{print $4 }'`;
proxy=`cat proxy.txt | awk '{print $1}'`;
echo /sbin/zfs receive -dF $pool > txt/replicate.txt 
datenow=`date +%m/%d/%Y`; timenow=`date +%T`;
logdata='Receiving_new_snapshot_for:'$vol'_from:'$partner;
logthis=`./jsonthis3.sh Date $datenow time $timenow msg info user $partner data $logdata`;
oldlog=`cat $logging | sed 's/]//g'`; newlog=$oldlog,$logthis]; echo $newlog > $logging;
echo $datenow $timenow :$logdata > ${logging}2
echo ready ;
