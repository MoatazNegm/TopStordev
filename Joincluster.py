#!/usr/bin/python3
from logqueue import queuethis, initqueue
from etcdput import etcdput as put 
from etcddel import etcddel as dels 
from etcdget import etcdget as get 
import logmsg
from time import sleep
from time import time as stamp

discip = '10.11.11.253'
def dosync(sync, *args):
  global leaderip, leader
  dels(leaderip, 'sync',sync)
  put(leaderip, *args)
  put(leaderip, args[0]+'/'+leader,args[1])
  return 

def valueof(etcdip, key):
 # the value of one key, or '' when it is not there (etcdget answers '_1' / '-1' / nothing)
 try:
  val = str(get(etcdip, key)[0])
 except:
  return ''
 if val in ('', '_1', '-1'):
  return ''
 return val

def do(data):
 global leaderip, discip, myhost, leader
 name=data['name']
 user=data['user']
 leaderip = data['leaderip']
 myhost = data['myhost']
 print('hihihihihhh', leaderip)
 leader = get(leaderip, 'leader')[0]
 logmsg.initlog(leaderip, myhost)
 initqueue(leaderip, myhost)
 # The node acknowledged an earlier join and has not announced itself again (an announcing node
 # deletes its own ackjoin): it is on its way, nothing to send.
 if valueof(discip, 'ackjoin/'+name):
  data['joinstatus'] = 'already acknowledged'
  return
 # tojoin is still waiting for the node to read it
 if valueof(discip, 'tojoin/'+name):
  data['joinstatus'] = 'pending'
  return
 queuethis('AddHost','running',user)
 logmsg.sendlog('AddHostst01','info',user,name)
 # the address the node is announcing from now (the node deletes its possible/ key once it acknowledges)
 nodenow = ''
 for _ in range(5):
  nodenow = valueof(discip, 'possible/'+name) or valueof(leaderip, 'possible/'+name)
  if '.' in nodenow:
   break
  sleep(2)
 if '.' not in nodenow:
  logmsg.sendlog('AddHostfa01','error',user,name)
  queuethis('AddHost','stop',user)
  data['joinstatus'] = 'node not announcing'
  return
 # what the node gets, in one line: tojoin/<name> = key=value|key=value|...
 cluip = (get(leaderip, 'namespace/mgmtip') or [leaderip])[0]
 if '.' not in str(cluip):
  cluip = leaderip
 if '/' not in str(cluip):
  cluip = str(cluip)+'/24'
 newip = ''
 if data.get('ipaddr'):
  newip = str(data['ipaddr'])
  if '/' not in newip:
   newip += '/'+str(data.get('ipaddrsubnet') or '24')
 fields = []
 if newip:
  fields.append('ip='+newip)
 fields.append('cip='+str(cluip))
 if data.get('alias'):
  fields.append('alias='+str(data['alias']))
 # the primary's node address (its software git-daemon) and branch, so the node pulls them before it restarts
 leadernodeip = (get(leaderip, 'ready/'+leader) or [''])[0]
 cversion = (get(leaderip, 'cversion/'+leader) or [''])[0]
 if '.' in str(leadernodeip) and '-' in str(cversion):
  fields.append('sw='+str(leadernodeip))
  fields.append('br='+str(cversion).rsplit('-',1)[0])
 joints = str(int(stamp()))
 fields.append('ts='+joints)
 joinline = '|'.join(fields)
 # publish and wait for the node's ackjoin/<name> = ts. The put is repeated while the node has not
 # read it: the discovery etcd can be recreated by a discovery scan right now.
 acked = False
 for attempt in range(11):
  if valueof(discip, 'ackjoin/'+name) == joints:
   acked = True
   break
  if attempt == 10:
   break
  if not valueof(discip, 'tojoin/'+name):
   if valueof(discip, 'ackjoin/'+name) == joints:
    acked = True
    break
   put(discip, 'tojoin/'+name, joinline)
  sleep(3)
 dels(discip, 'tojoin/'+name)
 if not acked:
  logmsg.sendlog('AddHostfa01','error',user,name)
  queuethis('AddHost','stop',user)
  data['joinstatus'] = 'not acknowledged'
  return
 # the node has its files and is on its way: it is in the cluster now, shown off until it is ready
 nameip = newip.split('/')[0] if newip else nodenow
 put(leaderip, 'allowedPartners',name)
 put(leaderip, 'ActivePartners/'+name, nameip)
 if newip:
  put(leaderip, 'ipaddr/'+name, newip)
 dosync('Partnr_str_', 'sync/allowedPartners/Add_'+name+'_'+nameip+'/request','Partnr_str_'+str(stamp()))
 dosync('Partnr_str_', 'sync/ActivePartners/Add_'+name+'_'+nameip+'/request','Partnr_str_'+str(stamp()))
 dels(leaderip,'possible',name)
 data['joinstatus'] = 'acknowledged'
 queuethis('AddHost','stop',user)

if __name__=='__main__':
 data = { 'name' : 'dhcp195391', 'user':'admin' , 'leaderip': '10.11.11.100', 'myhost': 'dhcp932129' }
 do(data)
