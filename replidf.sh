#!/usr/local/bin/zsh
logging='/usr/local/www/apache24/data/des19/Data/currentinfo2.log'
res=`echo $@ | awk '{print $1}'`;
localrep=`echo $@ | awk '{print $2}'`;
vol=`echo $@ | awk '{print $3}'`;
#pp=`echo $localrep | awk '{print $2}'`;
if [[ $localrep == "proxy" ]];
then
 pp=`cat workingpp | awk '{print $1}'`;
else
 pp=`cat workingpplocal | awk '{print $1}'`;
fi
pp=$((pp+2));
tun=`echo $@ | awk '{print $4 }'`;
partner=`echo $@ | awk '{print $5 }'`;
pool='Data';
echo $localrep >> tmp2repli
if [[ $localrep == "proxy" ]];
then
 echo /usr/bin/nc -ld $tun $pp \|  zfs receive -dF  $pool > tmprepli;
 /usr/bin/nc -ld $tun $pp |  zfs receive -dF  $pool 2>>tmprepli &;
else
 nc -ld $tun $pp | gunzip | openssl enc -d -aes-256-cbc -a -A -k SuperSecretPWD |zfs receive -dF  $pool 2>tmprepli &;
 echo nc -ld $tun $pp \| gunzip \| openssl enc -d -aes-256-cbc -a -A -k SuperSecretPWD \|zfs receive -dF  $pool >>tmprepli;
fi
prot=`zfs get -H prot:kind $vol/$pool | awk '{print $3}'`
if [[ $prot == "CIFS" ]]; then ./RepliCIFS $vol;fi
if [[ $prot == "NFS" ]];  then ./RepliNFS $vol;fi
./GetPoolVollist;
datenow=`date +%m/%d/%Y`; timenow=`date +%T`;
logdata='Receiving_new_snapshot_for:'$vol'_from:'$partner;
logthis=`./jsonthis3.sh Date $datenow time $timenow msg info user $partner data $logdata`;
oldlog=`cat $logging | sed 's/]//g'`; newlog=$oldlog,$logthis]; echo $newlog > $logging;
echo $datenow $timenow :$logdata > ${logging}2
echo ready > $res
