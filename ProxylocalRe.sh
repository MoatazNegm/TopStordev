#! /usr/local/bin/zsh
logging='/usr/local/www/apache24/data/des19/Data/currentinfo2.log'
proxy="10.3.2.6"
pp=$(( 3000+( $(od -An -N2 -i /dev/random) )%(4000-1024+1) ))
pass="jojo"
license="iwlanwlanwlanwlan"
sender="10.3.2.8";
receiver="10.3.2.7";
stamp=`date +%s`
echo $sender $stamp $pass $license ProxyrcvReInit.sh $receiver $pp | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -N $proxy 2234
mkfifo txt/in$pp;
mkfifo txt/out$pp;
#nc -lk $pp < txt/in$pp  &
./ProxylocalReClose.sh $pp &
echo waiting | nc -N $proxy $pp > txt/out$pp;
echo waiting > txt/in$pp &
./ProxylocalReInit.sh $pp $proxy &
echo $pp
