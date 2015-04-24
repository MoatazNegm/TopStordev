#! /usr/local/bin/zsh 
logging='/usr/local/www/apache24/data/des19/Data/currentinfo2.log'
cd /TopStor
pp=`echo $@ | awk '{print $1}'`;
proxy=`echo $@ | awk '{print $2}'`;
while true; do
counter=0;
isproxy=`cat partners.txt | grep -w sender | grep -w true | wc -c`;
echo isproxy=$isproxy, 
while [[ $isproxy -ge 3 ]]; do read -t 2 -r line;
 counter=$((counter+1));
 e="";
 linen=` echo $line | wc -c `;
 echo $line is line
 if [[ $linen -ge 2 ]]; then e=$line; fi;
 counter=$((counter+1));
 if [[ $counter -ge 30 ]]; 
 then
   counter=0; isproxy=`cat partners.txt | grep -w true | wc -c`;
 fi; 
 line="";
 echo $e | nc -N $proxy $pp > txt/out$pp;
 done < txt/in$pp 
done
