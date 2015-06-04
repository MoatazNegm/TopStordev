#! /usr/local/bin/zsh
logging='/usr/local/www/apache24/data/des19/Data/currentinfo2.log'
cd /TopStor
filepp=`echo $@ | awk '{print $1}'`;
 tail -f "$filepp" > ${filepp}f
