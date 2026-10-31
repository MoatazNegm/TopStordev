#!/usr/bin/python3
import subprocess,sys, datetime, re
from logqueue import queuethis
import json
from etcdgetpy import etcdget as get
from ast import literal_eval as mtuple
from socket import gethostname as hostname
from sendhost import sendhost
# QSD5.343: same API key rule as privthis.sh and fapi.has_privilege(): a name without usersinfo/<name> that is an active
# 'write' key (apikeys/<name> = write/active/...) has every privilege except these; a read key has none.
APIKEY_DENIED_PRIVS = ('UserPrivilegesch', 'Box_Users', 'Box_users', 'Uploadch', 'Error')
APIKEY_NAME_RE = re.compile(r'^[A-Za-z][A-Za-z0-9_-]{2,31}$')

def apikeypriv(etcd, priv, userreq):
 if not priv or priv in APIKEY_DENIED_PRIVS or not APIKEY_NAME_RE.match(str(userreq)):
  return 'False'
 try:
  rec = str(get(etcd, 'apikeys/'+userreq)[0])
 except Exception:
  return 'False'
 return 'true' if rec.startswith('write/active/') else 'False'

def privthis(*bargs):
 etcd = bargs[0]
 priv = bargs[1]
 userreq = bargs[2]
 if userreq in ['admin','system']:
  return 'true'
 userpriv = get(etcd, 'usersinfo/'+userreq)
 if str(userpriv[0] if userpriv else '_1') in ('_1', '-1', '', 'None'):
  return apikeypriv(etcd, priv, userreq)
 if priv in str(userpriv) and str(userpriv) != '-1':
   return userpriv[0].split(priv+'-')[1].split('/')[0]
 else:
  return 'False'

if __name__=='__main__':
 privthis(*sys.argv[1:])
