#!/usr/local/bin/zsh
logging='/var/www/html/des20/Data/currentinfo2.log'
res=`echo $@ | awk '{print $1}'`;
localrep=`echo $@ | awk '{print $2}'`;
echo $@ > tmp2repli
if [[ $localrep == 'proxy' ]];
then
 pp=`cat workingpp | awk '{print $1}'`;
 echo local=${localrep}hi >> tmp2repli;
else
 pp=`cat workingpplocal | awk '{print $1}'`;
 echo itislocal=${localrep}hi >> tmp2repli;
fi
#pp=`echo $@ | awk '{print $2}'`;
pp=$((pp+2));
tun=`echo $@ | awk '{print $4 }'`;
partner=`echo $@ | awk '{print $5 }'`;
pool=`echo $@ | awk '{print $6 }'`;
vol=`echo $@ | awk '{print $7 }'`;
initsnap=`echo $@ | awk '{print $8 }'`;
echo oper=$@ >> tmp2repli
zfs rollback -Rf $initsnap 2>/dev/null;
if [[ $localrep == 'proxy' ]];
then
 echo /usr/bin/nc -l $tun $pp \|  zfs receive -dvF  $pool > tmprepli
# /usr/bin/nc -ld $tun $pp |  zfs receive -dvF  $pool >zfsrec 2>>tmprepli&
else
 echo nc -l $tun $pp \|zfs receive -dvF  $pool >zfsrec 2>>tmprepli
# nc -ld $tun $pp | gunzip | openssl enc -d -aes-256-cbc -a -A -k SuperSecretPWD |zfs receive -dvF  $pool >zfsrec 2>>tmprepli &
fi
./RepliVolall $@ &
./GetPoolVollist
datenow=`date +%m/%d/%Y`; timenow=`date +%T`;
logdata='Receiving_new_snapshot_for:'$vol'_from:'$partner;
logthis=`./jsonthis3.sh Date $datenow time $timenow msg info user $partner data $logdata code Replivol1000@@@$vol@$partner`;
oldlog=`cat $logging | sed 's/]//g'`; newlog=$oldlog,$logthis]; echo $newlog > $logging;
echo Replivol1000@$datenow@$timenow@$vol@$partner > ${logging}2
echo ready > $res
