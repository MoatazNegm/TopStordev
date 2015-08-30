#!/usr/local/bin/zsh
cd /TopStor
traf='/usr/local/www/apache24/data/des19/Data/ctr.log'
disks=`/sbin/sysctl kern.disks | awk '{$1=""; print substr($0,2)}'`
noofdisks=`echo $disks | wc -w `;
traffic="";
s=0
while (( $s < $noofdisks )) 
do
disknow=` echo $disks | awk '{print $1}'`;
./updatetraffic.sh  $disknow $traf;
disks=` echo $disks | awk '{$1=""; print }'`;
s=$(( s+1 ));
done
