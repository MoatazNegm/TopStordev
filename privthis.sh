#!/bin/sh
export ETCDCTL_API=3
cd /TopStor
userpriv='/var/www/html/des20/Data/userpriv.txt';
userreq=` echo $@ | awk '{print $2}'`;
modpriv=` echo $@ | awk '{print $1}'`;
superuser='admin';
sysuser='system';
# QSD5.343: an API key (fapi.py, apikeys/<name>) is not a user: there is no usersinfo/<name>.  The executors get the key
# name as userreq (it is the audit user), so a key is judged here by the API's own rule, the same in fapi.has_privilege()
# and privthis.py: an active 'write' key has every privilege except the ones of the calls a key may never make
# (APIKEY_NEVER: users, groups, privileges, software; node config/join stay refused as before); a read key has none.
# Keep the list in step with APIKEY_DENIED_PRIVS in fapi.py and privthis.py.
apikeydenied=' UserPrivilegesch Box_Users Box_users Uploadch Error '
if [[ $sysuser == $userreq || $superuser == $userreq ]];
then
  echo true;
else
 rawinfo=`docker exec etcdclient /TopStor/etcdgetlocal.py usersinfo/$userreq`
 if [[ -z "$rawinfo" || "$rawinfo" == '_1' || "$rawinfo" == '-1' ]] && echo "$userreq" | grep -Eq '^[A-Za-z][A-Za-z0-9_-]{2,31}$';
 then
  keyrec=`docker exec etcdclient /TopStor/etcdgetlocal.py apikeys/$userreq`
  if [ -n "$modpriv" ] && echo "$keyrec" | grep -q '^write/active/' && ! echo "$apikeydenied" | grep -q " $modpriv ";
  then
   echo true;
  else
   echo 'false'
  fi
  exit 0
 fi
 userinfo=`echo "$rawinfo" | awk -F"$modpriv" '{print $2}'`
 priv=`echo $userinfo | cut -c 2- |  awk -F'/' '{print $1}'`
 echo $priv | grep 'true' >/dev/null
 if [ $? -eq 0 ];
 then
   echo $priv;
 else
  echo 'false'
 fi
fi
