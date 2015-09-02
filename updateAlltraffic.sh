#!/usr/local/bin/zsh
cd /TopStor
traf='/usr/local/www/apache24/data/des19/Data/ctr.log'
#traf='ctr.tmp'
disks=`/sbin/sysctl kern.disks | awk '{$1=""; print substr($0,2)}'`
noofdisks=`echo $disks | wc -w `;
traffic="";
s=0
while (( $s < $noofdisks )) 
do
ds=`wc -c $traf` 
echo $ds >> tmpds
/qstor/io-scripts/arcive-traffic/vlidatejson.sh $traf | grep Good 2&1>/dev/null
if [[ $? -eq 0 ]];
then
 disknow=` echo $disks | awk '{print $1}'`;
 nice -19 ./addtime.sh  $disknow $traf;
 disks=` echo $disks | awk '{$1=""; print }'`;
 s=$(( s+1 ));
else
 sleep 5;
fi
done
