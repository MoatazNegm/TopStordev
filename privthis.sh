#! /usr/local/bin/zsh
# needed the operands to be like : one:two:three:four
userreq=` echo $@ | awk '{print $2}'`;
modpriv=` echo $@ | awk '{print $1}'`;
superuser='admin';
if [[ $superuser == $userreq ]];
then
  echo true;
else
userpriv=` cat userpriv.txt | grep "$userreq"`;
rr=$modpriv\":\";
priv=`echo ${userpriv##*"$rr"} | awk -F\" '{print $1}'`;
echo $priv;
fi
