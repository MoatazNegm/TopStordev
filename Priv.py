#!/usr/bin/python3
import sys, subprocess
from etcdget import etcdget as get
from etcddel import etcddel as dels 
from etcdput import etcdput as put
from time import time as stamp
import logmsg

def dosync(leader, leaderip, sync, *args):
  dels(leaderip, sync)
  put(leaderip, *args)
  put(leaderip, args[0]+'/'+leader,args[1])
  return 


def changepriv(leader, leaderip, myhost, myip, user,priv,request='admin'):
 with open('/root/Privtmp','w') as f:
  f.write(' '.join([leader, leaderip, myhost, myip, user,priv,request])+'/n')
 logmsg.initlog(leaderip,myhost)
 if leader == myhost:
    etcdip = leaderip
 else:
    etcdip = myip
 syspriv = 'UserPrivilegesch'
 cmdline = ['/TopStor/privthis.sh',syspriv, request]
 res = subprocess.run(cmdline,stdout=subprocess.PIPE).stdout
 if 'true' not in res.decode('utf-8'):
  return
 # QSD5.341: a user that does not exist is refused; it used to write usersinfo/<name>=_1/<priv> and break users/userlist
 # QSD5.352 r9c (prover r4 D8): only a real user record ('<uid>:<gid>:/<pool>/<name>/<size>...') is rewritten.  A junk
 # 'usersinfo/<home name>' = '_1///<size>' (a HOME create for a name without a record, before r9) has 4 fields and was
 # kept and extended here; such a value stopped the user sync of every joining node (usersyncall.thread_add)
 import re
 userinfo = get(etcdip,'usersinfo/'+user)
 if not user or str(userinfo[0]) in ('_1', '-1', '', 'None') or len(str(userinfo[0]).split('/')) < 4 \
    or not re.match(r'^[0-9]+:[0-9]+:$', str(userinfo[0]).split('/')[0]):
  logmsg.sendlog('Priv1005','error',request,user)
  return
 logmsg.sendlog('Priv1002 ','info',request,user)
 leftpart = userinfo[0].split('/')[0:4]
 put(leaderip, 'usersinfo/'+user, '/'.join(leftpart)+'/'+priv)
 dosync(leader, leaderip, 'sync/priv/'+user,'sync/priv/'+user+'/request', 'priv_'+user+'_'+str(stamp()))
 #put(leaderip, 'user/'+myhost,str(stamp()))
 #broadcasttolocal('usersinfo/'+user, '/'.join(leftpart)+'/'+priv)
 print('/'.join(leftpart)+'/'+priv)
 logmsg.sendlog('Priv1003','info',request,user)
 
 return


if __name__=='__main__':
 changepriv(*sys.argv[1:])

