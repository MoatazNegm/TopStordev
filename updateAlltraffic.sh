#! /usr/local/bin/zsh
cd /TopStor/
traf='txt/currenttraffic2.log'
disks=`sysctl kern.disks | awk '{$1=$2=$3=""; print}'`
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
