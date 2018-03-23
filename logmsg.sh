#!/usr/bin/sh
logging='/var/www/html/des20/Data/currentinfo2.log'
glog='/var/www/html/des20/Data/TopStor.log'
msg=` echo $@ | awk '{print $1}'`;
msgtype=` echo $@ | awk '{print $2}'`;
msguser=` echo $@ | awk '{print $3}'`;
datenow=`date +%m/%d/%Y`; timenow=`date +%T`;
logcode=$msg'@'$datenow'@'$timenow
x=4; code=$msg'@@'; 
while [ $x -le $# ]; do
 logcode=$logcode'@'`echo $@ | awk -v xx=$x '{print $xx}'`;
 code=$code'@'`echo $@ | awk -v xx=$x '{print $xx}'`;
 x=$((x+1));
done
echo code=$code
echo logcode=$logcode
echo $logcode > ${logging}2
dt=${datenow}'T'${timenow}; dtn=`date +%s -d $dt`;
echo $datenow $timenow $msgtype $msguser $code $dtn>> $glog
