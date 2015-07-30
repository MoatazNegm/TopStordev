#! /bin/sh
logging='/usr/local/www/apache24/data/des19/Data/currentinfo2.log'
res=`echo $@ | awk '{print $1}'`;
pp=`echo $@ | awk '{print $2}'`;
tun=`echo $@ | awk '{print $3 }'`;
partner=`echo $@ | awk '{print $4 }'`;
pool=`echo $@ | awk '{print $5 }'`;
vol=`echo $@ | awk '{print $6 }'`;
echo /usr/bin/nc -ld $tun $pp \|  zfs receive -dF  $pool > tmprepli
/usr/bin/nc -ld $tun $pp |  zfs receive -dF  $pool &
datenow=`date +%m/%d/%Y`; timenow=`date +%T`;
logdata='Receiving_new_snapshot_for:'$vol'_from:'$partner;
logthis=`./jsonthis3.sh Date $datenow time $timenow msg info user $partner data $logdata`;
oldlog=`cat $logging | sed 's/]//g'`; newlog=$oldlog,$logthis]; echo $newlog > $logging;
echo $datenow $timenow :$logdata > ${logging}2
echo ready > $res
