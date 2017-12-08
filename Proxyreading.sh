#!/usr/local/bin/zsh
logging='/usr/local/www/apache24/data/des19/Data/currentinfo2.log'
cd /TopStor
filepp=`echo $@ | awk '{print $1}'`;
while true ;
do
/usr/local/bin/socat -u PIPE:$filepp GOPEN:${filepp}f
done;
