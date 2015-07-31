#! /usr/local/bin/zsh
cd /TopStor
openvpnflag=0
stamp=`date +%s`;
while true;
do
 while read line;
 do
  isproxy=`echo $line | awk '{print $3}'`;
  if [[ $isproxy != "true" ]]; then; break; fi
  dst=`echo $line | awk '{print $1}'`;
  passphrase=`echo $line | awk '{print $4}'`;
  pp=`echo $line | awk '{print $5}'`;
  proxyser=`cat proxy.txt | awk '{print $1}'`;
  license=` cat proxy.txt | awk '{print $2}'`;
  so=` cat proxy.txt | awk '{print $3}'`;
  tun=`(ifconfig tun0 | grep -w 'inet' | awk '{print $2}') 2>/dev/null`
  istun=`echo $tun | awk -F. '{print $1}'`;
  istunn=$((istun+1))
   echo istun=$istun >> tmpprox
  if [[ $istunn -ge 5 ]];
  then
   ps -auxw | grep ProxyncSVC > /dev/null 2>&1;
   echo router=$router >> tmpprox
   if [[ $? -ne 0 ]];
   then
    ./ProxyncSVC $pp $tun sender &;
    echo ncSVC starting >> tmpprox
   fi
   router=`echo $tun | awk -F. '{print $1"."$2"."$3".1"}'`
   echo router=$router >> tmpprox
   /sbin/ping -c 2 $router >/dev/null 2>&1
   if [[ $? -ne 0 ]];
   then
    echo no ping >> tmpprox
    openvpnflag=0;
    killall openvpn;
    ispid=`ps -axw  | grep nc | grep "$pp" | grep -v Proxy | awk '{print $1}'`;
    if [[ $? -eq 0 ]]; then kill -TERM $ispid 2>/dev/null; fi
    ppzfs=$((pp+1));
    ispid=`ps -axw  | grep nc | grep "$ppizfs" | grep -v Proxy | awk '{print $1}'`;
    if [[ $? -eq 0 ]]; then kill -TERM $ispid 2>/dev/null; fi
    echo first stage >> tmpprox
   fi
   echo second stage >> tmpprox
  fi
  echo third  stage >> tmpprox
  if [[ openvpnflag -eq 0 ]];
  then 
   openvpnflag=1;
   echo $so $stamp $dst $license ProxyInit $so $pp $passphrase $dst  | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -w 4 -N $proxyser 2234
   echo 4th  stage >> tmpprox
  fi 
  ispid=`ps -axw | grep openvpn | grep "$dst"`
  echo 5th  stage >> tmpprox
  ispidn=`echo $ispid | wc -c `
  echo 6th  stage >> tmpprox
  if [[ -a txt/$pp && $ispidn -ge 5 ]]; then echo killing ispid >> tmpprox; kill -TERM `echo $ispid | awk '{ print $1}'`; fi
  echo passed first killing:$pp $ispidn  >> tmpprox
  if [[ -a txt/$pp || $ispidn -le 3 ]];
  then
   echo removing txt/$pp >> tmpprox;
   rm txt/$pp 2>/dev/null;  
   proxy=$proxyser
   port=$pp;
   sed -e "s/PROXY/$proxy/g" -e "s/PORT/$port/g" openvpn.conf > txt/${so}_${dst}_openvpn.conf;
   /usr/local/sbin/openvpn --daemon $dst --cd /TopStor/txt --config ${so}_${dst}_openvpn.conf; 
  fi
 echo 7th  stage >> tmpprox
 tun=`(ifconfig tun0 | grep -w 'inet' | awk '{print $2}') 2>/dev/null`
 istun=`echo $tun | awk -F. '{print $1}'`;
 istunn=$((istun+1))
 echo 8th  stage istunn=$istunn >> tmpprox
 if [[ $istunn -ge 5 ]];
 then
 echo 9th  stage istunn=$istunn >> tmpprox
  echo ps -awx \| grep Askrcv \| grep "$tun" \| grep "$pp" \| grep -v "$stamp"   >> tmpprox
  otherask=`ps -awx | grep Askrcv | grep "$tun" | grep "$pp" | grep -v "$stamp"`
  if [[ $? -eq 0 ]]; then 
   kill -TERM ` echo $otherask | awk '{print $1}'` >/dev/null 2>&1 ;
   echo 10th stage other=$otherask >> tmpprox
  fi
  otherask=`ps -awx | grep Askrcv | grep "$tun" | grep "$pp" | grep -w "$stamp"`
  if [[ $? -ne 0 ]]; then 
  ./Askrcv $pp $tun $so $stamp &;
  fi
 fi
 done < partners.txt;
# sleep 1;
done;
