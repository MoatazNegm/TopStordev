#! /bin/sh
logging='/usr/local/www/apache24/data/des19/Data/currentinfo2.log'
pp=`echo $@ | awk '{print $1}'`;
pool=`echo $@ | awk '{print $2 }'`;
partner=`echo $@ | awk '{print $3 }'`;
vol=`echo $@ | awk '{print $4 }'`;
/usr/bin/nc -l $pp | gunzip | openssl enc  -d  -a -A -aes-256-cbc -k SuperSecretPWD | zfs receive -dF  $pool &
datenow=`date +%m/%d/%Y`; timenow=`date +%T`;
logdata='Receiving_new_snapshot_for:'$vol'_from:'$partner;
logthis=`./jsonthis3.sh Date $datenow time $timenow msg info user $partner data $logdata`;
oldlog=`cat $logging | sed 's/]//g'`; newlog=$oldlog,$logthis]; echo $newlog > $logging;
echo $datenow $timenow :$logdata > ${logging}2
echo ready ;
