#!/usr/local/bin/zsh
cd /TopStor
ctr="/usr/local/www/apache24/data/des19/Data/ctr.log";
ctr2="/usr/local/www/apache24/data/des19/Data/ctr.log.";
info="/usr/local/www/apache24/data/des19/Data/currentinfo2.log";
backlist=`ls ${ctr2}* | grep back | awk -F"back" '{print $1}' `; 
echo $backlist | while read -r l; do; ./ssperfcheck $l; rm ${l}back 2>/dev/null; done;
todayd=`date +%y%m%d`;
todaylog=${ctr2}${todayd};
if [[ -e $todaylog ]];
then 
 ./ssperfcheck $todaylog;
 ./checkjson $todaylog;
 if [[ $? -ne 0 ]]; then echo > $todaylog; fi
else
 echo > $todaylog;
fi
./ssperfcheck $ctr;
./checkjson $ctr;
if [[ $? -ne 0 ]]; then echo > $ctr; fi
./ssperfcheck $info;
./checkjson $info;
if [[ $? -ne 0 ]]; then echo > $info; fi
starting=`date +%s`
starting=$((starting+0));
while true; do
{
nowt=`date +%s`
nowt=$((nowt+0));
difft=$(( nowt-starting ));
if [[ $difft -ge 300 ]];
then
 ./ssperfcheck $ctr;
 ./ssperfcheck $info;
 ./ssperfcheck $todaylog;
 nextday=`date +%y%m%d`;
 if [[ $todayd != $nextday ]]; 
 then
  rm ${todaylog}back 2>/dev/null
  todaylog=${ctr2}${nextday}; 
  echo > $todaylog;
  todayd=$nextday;
 fi
 starting=$nowt
fi
./updateAlltraffic.sh $todaylog
#./updateAlltraffic.sh $ctr
sleep 3
}
done;
