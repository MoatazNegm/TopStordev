#! /usr/local/bin/zsh
cd /TopStor
openvpnflag=0
stamp=`date +%s`;
while true;
do
 proxyser=`cat proxy.txt | awk '{print $1}'`;
 license=` cat proxy.txt | awk '{print $2}'`;
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
  istun=`echo $tun | awk -F. '{print $1}'`;
  istunn=$((istun+1))
  if [[ $istunn -ge 5 ]];
  then
   if [[ $localrep == "proxy" ]];
   then
    ps -auxw | grep ProxyncSVC > /dev/null 2>&1;
    if [[ $? -ne 0 ]];
    then
     ./ProxyncSVC $pp $tun sender &;
    fi
    router=`echo $tun | awk -F. '{print $1"."$2"."$3".1"}'`
    /sbin/ping -c 2 $router >/dev/null 2>&1
    if [[ $? -ne 0 ]];
    then
     openvpnflag=0;
     killall openvpn;
     ispid=`ps -axw  | grep nc | grep "$pp" | grep -v Proxy | awk '{print $1}'`;
     if [[ $? -eq 0 ]]; then kill -TERM $ispid 2>/dev/null; fi
     ppzfs=$((pp+1));
     ispid=`ps -axw  | grep nc | grep "$ppzfs" | grep -v Proxy | awk '{print $1}'`;
     if [[ $? -eq 0 ]]; then kill -TERM $ispid 2>/dev/null; fi
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
   if [[ -a txt/$pp && $ispidn -ge 5 ]]; then  kill -TERM `echo $ispid | awk '{ print $1}'`; fi
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
   otherask=`ps -awx | grep Askrcv | grep "$tun" | grep "$pp" | grep -v "$stamp"`
   if [[ $? -eq 0 ]]; then 
    kill -TERM ` echo $otherask | awk '{print $1}'` >/dev/null 2>&1 ;
   fi
   otherask=`ps -awx | grep Askrcv | grep "$tun" | grep "$pp" | grep -w "$stamp"`
   if [[ $? -ne 0 ]]; then 
    ./Askrcv $pp $tun $so $stamp $localrep &;
   fi
  fi
 done < partners.txt;
#  sleep 1;
done;
