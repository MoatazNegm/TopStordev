#!/usr/local/bin/zsh
cd /TopStor
traf=$1
if [[ -a txt/stopperf ]]; then sleep 2;
else
 disks=`/sbin/sysctl kern.disks | awk '{$1=""; print substr($0,2)}'`
 noofdisks=`echo $disks | wc -w `;
 s=0
 touch ${traf}wait
 while (( $s < $noofdisks )) 
 do
  disknow=` echo $disks | awk '{print $1}'`;
 if [[ $disknow != "cd0" ]];
 then
 nice -19 ./addtime.sh  $disknow $traf;
 fi;
 disks=` echo $disks | awk '{$1=""; print }'`;
 s=$(( s+1 ));
 done
rm ${traf}wait 2>/dev/null
fi
