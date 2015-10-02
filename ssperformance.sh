#!/usr/local/bin/zsh
ctr="/usr/local/www/apache24/data/des19/Data/ctr.log"
info="/usr/local/www/apache24/data/des19/Data/currentinfo2.log"
cd /TopStor
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
 starting=$nowt
fi
./updateAlltraffic.sh
sleep 3
}
done;
