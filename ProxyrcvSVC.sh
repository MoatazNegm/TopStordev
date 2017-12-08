#!/usr/local/bin/zsh
cd /TopStor
while true;
do
 while read line;
 do
  isproxy=`echo $line | awk '{print $3}'`;
  issender=`echo $line | awk '{print $2}'`;
  if [[ $isproxy != "true" || $issender != "sender" ]]; then; break; fi
  dst=`echo $line | awk '{print $1}'`;
  passphrase=`echo $line | awk '{print $4}'`;
  pp=`echo $line | awk '{print $5}'`;
  stamp=`date +%s`;
  proxyser=`cat proxy.txt | awk '{print $1}'`;
  license=` cat proxy.txt | awk '{print $2}'`;
  so=` cat proxy.txt | awk '{print $3}'`;
  tun=`(ifconfig tun0 | grep -w 'inet' | awk '{print $2}') 2>/dev/null`
  istun=`echo $tun | awk -F. '{print $1}'`;
  istunn=$((istun+1))
  if [[ $istunn -ge 5 ]];
  then
   ps -auxw | grep ProxyncSVC > /dev/null 2>&1;
   if [[ $? -ne 0 ]];
   then
    ./ProxyncSVC $pp $tun sender &;
   fi
   router=`echo $tun | awk -F. '{print $1"."$2"."$3".1"}'`
   echo $router > tmpprox
   /sbin/ping -c 2 $router >/dev/null 2>&1
   if [[ $? -ne 0 ]];
   then
    echo no ping >> tmpprox
    killall openvpn;
    ispid=`ps -axw  | grep nc | grep "$pp" | grep -v Proxy | awk '{print $1}'`;
    if [[ $? -eq 0 ]]; then kill -TERM $ispid 2>/dev/null; fi
    ppzfs=$((pp+1));
    ispid=`ps -axw  | grep nc | grep "$ppizfs" | grep -v Proxy | awk '{print $1}'`;
    if [[ $? -eq 0 ]]; then kill -TERM $ispid 2>/dev/null; fi
   fi
  fi
  echo $so $stamp $dst $license ProxyInit $so $pp $passphrase $dst  | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -N $proxyser 2234
  ispid=`ps -axw | grep openvpn | grep "$dst"`
  ispidn=`echo $ispid | wc -c `
   echo $ispid $ispidn >> tmpprox
  if [[ -a txt/$pp && $ispidn -ge 5 ]]; then echo killing ispid >> tmpprox; kill -TERM `echo $ispid | awk '{ print $1}'`; fi
  echo passed first killing >> tmpprox
  if [[ -a txt/$pp || $ispidn -le 3 ]];
  then
   echo removing txt/$pp >> tmpprox;
   rm txt/$pp 2>/dev/null;  
   proxy=$proxyser
   port=$pp;
   sed -e "s/PROXY/$proxy/g" -e "s/PORT/$port/g" openvpn.conf > txt/${so}_${dst}_openvpn.conf;
   /usr/local/sbin/openvpn --daemon $dst --cd /TopStor/txt --config ${so}_${dst}_openvpn.conf; 
  fi
 tun=`(ifconfig tun0 | grep -w 'inet' | awk '{print $2}') 2>/dev/null`
 istun=`echo $tun | awk -F. '{print $1}'`;
 istunn=$((istun+1))
 if [[ $istunn -ge 5 ]];
 then
  otherask=`ps -awx | grep Askrcv | grep "$tun" | grep "$pp" | grep -v "$stamp"  >/dev/null 2>&1`
  if [[ $? -eq 0 ]]; then kill -TERM ` echo $otherask | awk '{print $1}'` >/dev/null 2>&1 ; fi
  ./Askrcv $pp $tun $so $stamp;
 fi
 done < partners.txt;
# sleep 1;
done;
