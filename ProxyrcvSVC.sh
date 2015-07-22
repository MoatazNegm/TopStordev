#!/usr/local/bin/zsh
cd /TopStor
while read line;
do
 isproxy=`echo $line | awk '{print $3}'`;
 issender=`echo $line | awk '{print $2}'`;
 if [[ $isproxy != "true" || $issender != "sender" ]]; then; exit; fi
 dst=`echo $line | awk '{print $1}'`;
 passphrase=`echo $line | awk '{print $4}'`;
pp=`echo $line | awk '{print $5}'`;
stamp=`date +%s`;
proxyser=`cat proxy.txt | awk '{print $1}'`;
license=` cat proxy.txt | awk '{print $2}'`;
so=` cat proxy.txt | awk '{print $3}'`;
lineflag="failed"
  echo $so $stamp $dst $license ProxyInit $so $pp $passphrase $dst  | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -N $proxyser 2234
proxy=$proxyser
port=$pp;
sed -e "s/PROXY/$proxy/g" -e "s/PORT/$port/g" openvpn.conf > txt/${so}_${stamp}_openvpn.conf;

/usr/local/sbin/openvpn --daemon $so --cd /TopStor/txt --config ${so}_${stamp}_openvpn.conf;

done < partners.txt
