#! /usr/local/bin/zsh
cd /TopStor
openvpnflag=0
stamp=`date +%s`;
proxycurrent=`cat proxy.txt | awk '{print $1}'`;
proxyname=`cat proxy.txt | awk '{print $3}'`;
isproxy="";
while true;
do
 proxyser=`cat proxy.txt | awk '{print $1}'`;
 license=` cat proxy.txt | awk '{print $2}'`;
 newproxy=` cat proxy.txt | awk '{print $3}'`;
 if [[ -a txt/PartnerDel ]]; 
 then PartnerDel=`cat txt/PartnerDel`;
  isproxy=`echo $PartnerDel | awk '{print $3}'`;
  echo to kill again >> tmptokill
 fi
 if [[ $proxycurrent != $proxyser || $newproxy != $proxyname || -a txt/PartnerDel ]];
 then
  openvpnflag=0;
  rm txt/PartnerDel 2>/dev/null 
  proxycurrent=$proxyser;
  proxyname=$newporxy;
  killall openvpn 2>/dev/null;
  kill -KILL `ps -axw | grep ProxyncSVC | awk '{print $1}'` 2>/dev/null;
  kill -KILL `ps -axw | grep Askrcv | awk '{print $1}'` 2>/dev/null;
  kill -KILL `ps -axw | grep nc | grep 3336 | awk '{print $1}'` 2>/dev/null;
  kill -KILL `ps -axw | grep nc | grep 3337 | awk '{print $1}'` 2>/dev/null;
  kill -KILL `ps -axw | grep nc | grep 2236 | awk '{print $1}'` 2>/dev/null;
  kill -KILL `ps -axw | grep nc | grep 2237 | awk '{print $1}'` 2>/dev/null;
  kill -KILL `ps -axw | grep zfs | grep send | awk '{print $1}'` 2>/dev/null;
  kill -KILL `ps -axw | grep zfs | grep receive | awk '{print $1}'` 2>/dev/null;
  kill -KILL `ps -axw | grep nc | grep 2238 | awk '{print $1}'` 2>/dev/null;
 fi
 while read line;
 do
  isproxy=`echo $line | awk '{print $3}'`;
  if [[ $isproxy != "true" ]]; then; localrep="local"; else localrep="proxy";fi
  dst=`echo $line | awk '{print $1}'`;
  if [[ $localrep == "proxy" ]];
  then
   passphrase=`echo $line | awk '{print $4}'`;
   pp=`echo $line | awk '{print $5}'`;
   so=` cat proxy.txt | awk '{print $3}'`;
   tun=`(ifconfig tun0 | grep -w 'inet' | awk '{print $2}') 2>/dev/null`
  else
   passphrase="pass";
   pp=`cat workingpplocal | awk '{print $1}'`;
   tun=`(ifconfig em1 | grep -w 'inet' | awk '{print $2}') 2>/dev/null`
   so=$tun
  fi 
  if [[ -n $tun ]];
  then
   if [[ $localrep == "proxy" ]];
   then
    ps -auxw | grep ProxyncSVC > /dev/null 2>&1;
    if [[ $? -ne 0 ]];
    then
     ./ProxyncSVC $pp $tun peer &;
    fi
   fi
   otherask=`ps -awx | grep Askrcv | grep "$tun" | grep "$pp" | grep -w "$stamp"`
   if [[ $? -ne 0 ]]; then
    ./Askrcv $pp $tun $so $stamp $localrep &;
   fi
  fi
  istun=`echo $tun | awk -F. '{print $1}'`;
  istunn=$((istun+1))
  if [[ $istunn -ge 5 ]];
  then
   if [[ $localrep == "proxy" ]];
   then
    ps -auxw | grep ProxyncSVC > /dev/null 2>&1;
    if [[ $? -ne 0 ]];
    then
     ./ProxyncSVC $pp $tun peer &;
    fi
    router=`echo $tun | awk -F. '{print $1"."$2"."$3".1"}'`
    /sbin/ping -c 3 $router >/dev/null 2>&1
    if [[ $? -ne 0 ]];
    then
     openvpnflag=0;
     killall openvpn;
     kill -KILL `ps -axw | grep ProxyncSVC | awk '{print $1}'` 2>/dev/null;
     kill -KILL `ps -axw | grep Askrcv | awk '{print $1}'` 2>/dev/null;
     kill -KILL `ps -axw | grep nc | grep 3336 | awk '{print $1}'` 2>/dev/null;
     kill -KILL `ps -axw | grep nc | grep 3337 | awk '{print $1}'` 2>/dev/null;
     kill -KILL `ps -axw | grep nc | grep 2236 | awk '{print $1}'` 2>/dev/null;
     kill -KILL `ps -axw | grep nc | grep 2237 | awk '{print $1}'` 2>/dev/null;
     kill -KILL `ps -axw | grep zfs | grep send | awk '{print $1}'` 2>/dev/null;
     kill -KILL `ps -axw | grep zfs | grep receive | awk '{print $1}'` 2>/dev/null;
     kill -KILL `ps -axw | grep nc | grep 2238 | awk '{print $1}'` 2>/dev/null;
    fi
   fi
  fi
  if [[ $localrep == "proxy" ]];
  then
   if [[ openvpnflag -eq 0 ]];
   then 
    openvpnflag=1;
    echo $so $stamp $dst $license ProxyInit $so $pp $passphrase $dst  | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -w 4 -N $proxyser 2234 2>/dev/null
   fi 
   ispid=`ps -axw | grep openvpn | grep "$dst"`
   ispidn=`echo $ispid | wc -c `
   if [[ -a txt/$pp && $ispidn -ge 5 ]]; then kill -KILL `echo $ispid | awk '{ print $1}'`; fi
   if [[ -a txt/$pp || $ispidn -le 3 ]];
   then
    rm txt/$pp 2>/dev/null;  
    proxy=$proxyser
    port=$pp;
    sed -e "s/PROXY/$proxy/g" -e "s/PORT/$port/g" openvpn.conf > txt/${so}_${dst}_openvpn.conf;
    /usr/local/sbin/openvpn --daemon $dst --cd /TopStor/txt --config ${so}_${dst}_openvpn.conf; 
   fi
  fi
  if [[ $istunn -ge 5 ]];
  then
   otherask=`ps -awx | grep Askrcv | grep "$tun" | grep -vw "$pp" | grep -vw "$stamp"`
   if [[ $? -eq 0 ]]; then 
    kill -KILL ` echo $otherask | awk '{print $1}'` >/dev/null 2>&1 ;
   fi
  fi
  sleep 5;
  tun=`(ifconfig tun0 | grep -w 'inet' | awk '{print $2}') 2>/dev/null`
  if [[ $localrep == "proxy" && -n $tun ]];
  then
   echo $so $stamp $dst $license ProxyUpdate $so $pp $passphrase $dst  | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -w 4 -N $proxyser 2234 2>/dev/null
  ;
  fi
 done < partners.txt;
done;
