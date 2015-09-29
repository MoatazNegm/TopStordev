#!/usr/local/bin/zsh
logging='/usr/local/www/apache24/data/des19/Data/currentinfo2.log'
res=`echo $@ | awk '{print $1}'`;
prot=`echo $@ | awk '{print $6}'`;
vol=`echo $@ | awk '{print $7}'`;
partner=`echo $@ | awk '{print $5 }'`;
pool='Data';
if [[ $prot == "CIFS" ]]; then ./RepliCIFS $@ &; fi
if [[ $prot == "NFS" ]]; then ./RepliNFS $@ &; fi
datenow=`date +%m/%d/%Y`; timenow=`date +%T`;
logdata='Receiving_new_snapshot_for:'$vol'_from:'$partner;
logthis=`./jsonthis3.sh Date $datenow time $timenow msg info user $partner data $logdata`;
oldlog=`cat $logging | sed 's/]//g'`; newlog=$oldlog,$logthis]; echo $newlog > $logging;
echo $datenow $timenow :$logdata > ${logging}2
echo ready > $res
