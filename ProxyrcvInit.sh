#! /usr/local/bin/zsh 
logging='/usr/local/www/apache24/data/des19/Data/currentinfo2.log'
cd /TopStor
proxy=`cat proxy.txt | awk '{print $1}'`;
license=` cat proxy.txt | awk '{print $2}'`;
stamp=`date +%s`;
dst="10.3.2.8"
so="10.3.2.7";
while read line ;
do
 isproxy=`echo i$line | grep -w sender | grep -w true | wc -c`;
 echo isproxy=$isproxy, 
 if [[ $isproxy -ge 3 ]];
 then
  pp=`echo $line | awk '{print $5}'`;
  ppplus=$((pp+1));
  echo $so $stamp $dst $license ProxyrcvReInit.sh $so $pp | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -N $proxy 2234
  mkfifo txt/cout$pp; mkfifo txt/cin$ppplus; 
  ./ProxyReCloseSVC.sh $proxy $pp &;
  ./ProxyReClose.sh $proxy $pp &;
 fi 
done < partners.txt
