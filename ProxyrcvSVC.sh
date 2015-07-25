#! /usr/local/bin/zsh
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
 lineflag="failed"
 echo $so $stamp $dst $license ProxyInit $so $pp $passphrase $dst  | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -N $proxyser 2234
 ispid=`ps -xo pid -o command | grep openvpn | grep $dst`; 
 ispidn=`echo $ispid | wc -c `
 if [[ -f txt/$pp && $ispidn -ge 5 ]]; then kill -TERM `echo $ispid | awk '{ print $1}'`; fi
 if [[ -f txt/$pp || $ispidn -le 3 ]];
 then
  rm txt/$pp 2>/dev/null;  
  proxy=$proxyser
  port=$pp;
  sed -e "s/PROXY/$proxy/g" -e "s/PORT/$port/g" openvpn.conf > txt/${so}_${dst}_openvpn.conf;
  /usr/local/sbin/openvpn --daemon $dst --cd /TopStor/txt --config ${so}_${dst}_openvpn.conf; 
 fi
done < partners.txt;
sleep 10;
tun=`ifconfig tun0 | grep -w 'inet' | awk '{print $2}' 2>/dev/null`
istun=`echo $tun | awk -F. '{print $1}'`;
if [[ $istun -ge 5 ]];
then
 router=`echo $tun | awk -F. '{print $1"."$2"."$3".1"}'`
 ping -c 3 $router > /dev/null 2>&1
 if [[ $? -ne 0 ]]; then killall openvpn; 
 else nc -l $tun 2236 > txt/remotepeer &;
fi
fi
done;
