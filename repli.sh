#! /bin/sh
#! /bin/sh
pp=`echo $@ | awk '{print $1}'`;
pool=`echo $@ | awk '{print $2 }'`;
/usr/bin/nc -l $pp | gunzip | openssl enc  -d  -a -A -aes-256-cbc -k SuperSecretPWD | zfs receive -dF  $pool &


