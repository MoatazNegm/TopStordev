#! /bin/sh
logging='/usr/local/www/apache24/data/des19/Data/currentinfo2.log'
res=`echo $@ | awk '{print $1}'`;
localrep=`cat $res`;
#pp=`echo $@ | awk '{print $2}'`;
if [[ $localrep == "proxy" ]];
then
 pp=`cat workingpp | awk '{print $1}'`;
else
 pp=`cat workingpplocal | awk '{print $1}'`;
fi
pp=$((pp+2));
tun=`echo $@ | awk '{print $3 }'`;
partner=`echo $@ | awk '{print $4 }'`;
pool='Data';
if [[ $localrep == "proxy" ]];
then
 echo /usr/bin/nc -ld $tun $pp \|  zfs receive -dF  $pool > tmprepli
 /usr/bin/nc -ld $tun $pp |  zfs receive -dF  $pool &
else
 nc -ld $tun $pp | gunzip | openssl enc -d -aes-256-cbc -a -A -k SuperSecretPWD |zfs receive -dF  $pool 2>tmprepli &
 echo nc -ld $tun $pp \| gunzip \| openssl enc -d -aes-256-cbc -a -A -k SuperSecretPWD \|zfs receive -dF  $pool >>tmprepli
fi
datenow=`date +%m/%d/%Y`; timenow=`date +%T`;
logdata='Receiving_new_snapshot_for:'$vol'_from:'$partner;
logthis=`./jsonthis3.sh Date $datenow time $timenow msg info user $partner data $logdata`;
oldlog=`cat $logging | sed 's/]//g'`; newlog=$oldlog,$logthis]; echo $newlog > $logging;
echo $datenow $timenow :$logdata > ${logging}2
echo ready > $res
