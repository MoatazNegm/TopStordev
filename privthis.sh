#!/usr/local/bin/zsh
# needed the operands to be like : one:two:three:four
userpriv='/var/www/html/des20/Data/userpriv.txt';
userreq=` echo $@ | awk '{print $2}'`;
modpriv=` echo $@ | awk '{print $1}'`;
superuser='admin';
sysuser='system';
if [[ $sysuser == $userreq || $superuser == $userreq ]];
then
  echo true;
else
userpriv=` cat $userpriv | grep "$userreq"`;
rr=$modpriv\":\";
priv=`echo ${userpriv##*"$rr"} | awk -F\" '{print $1}'`;
echo $priv;
fi
