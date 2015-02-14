#! /usr/local/bin/zsh
cd /TopStor
traf='/usr/local/www/apache24/data/des19/Data/currenttraffic.log'
disks=`/sbin/sysctl kern.disks | awk '{$1=$2=$3=""; print}'`
noofdisks=`echo $disks | wc -w `;
traffic=`cat $traf`;
s=0
while (( $s < $noofdisks )) 
do
disknow=` echo $disks | awk '{print $1}'`;
traffic=`./updatetraffic.sh  $disknow $traffic`;
disks=` echo $disks | awk '{$1=""; print }'`;
s=$(( s+1 ));
done
echo $traffic > $traf
