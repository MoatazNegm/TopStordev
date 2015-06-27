#! /usr/local/bin/zsh 
logging='/usr/local/www/apache24/data/des19/Data/currentinfo2.log'
cd /TopStor
proxyf=`cat proxy.txt`;
proxy=`echo $proxyf | awk '{print $1}'`;
license=` echo $proxyf | awk '{print $2}'`;
so=` echo $proxyf | awk '{print $3}'`;
stamp=`date +%s`;
while read line ;
do
 isproxy=`echo $line | grep -w sender | grep -w true | wc -c`;
 #echo isproxy=$isproxy, 
 if [[ $isproxy -ge 3 ]];
 then
  dst=`echo $line | awk '{print $1}'`;
  passphrase=`echo $line | awk '{print $4}'`;
  pp=`echo $line | awk '{print $5}'`;
  ppplus=$((pp+1));
  kill -9 `ps -axuw | grep  ProxyReClose | awk '{print $2}'` 2> /dev/null
  kill -9 `ps -axuw | grep Proxyread | awk '{print $2}'` 2> /dev/null
  kill -9 `ps -axuw | grep socat | awk '{print $2}'` 2> /dev/null
  echo echo $so $stamp $dst $license ProxyrcvReInit.sh $so $pp $passphrase $dst \| openssl enc -a -A -aes-256-cbc -k SuperSecretPWD \| gzip -cf \| nc -N $proxy 2234 > proxyinit${pp}.sh
  chmod 700 proxyinit${pp}.sh
  ./ProxyReCloseSVC.sh $proxy $pp $dst &;
  sleep 1;
  ./ProxyReClose.sh $pp $dst &;
  sleep 1;
  ./Proxyreading.sh txt/cout$pp $dst &
 fi 
done < partners.txt
