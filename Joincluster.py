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
 queuethis('AddHost','running',user)
 logmsg.sendlog('AddHostst01','info',user,name)
 cluip = (get(leaderip, 'namespace/mgmtip') or [leaderip])[0]
 if '.' not in str(cluip):
  cluip = leaderip
 if '/' not in str(cluip):
  cluip = str(cluip)+'/24'
 # tell the joining node which software to pull before it restarts: the primary's
 # node address (its software git-daemon) and branch; these must be put BEFORE tojoin/
 leadernodeip = (get(leaderip, 'ready/'+leader) or [''])[0]
 cversion = (get(leaderip, 'cversion/'+leader) or [''])[0]
 if '.' in str(leadernodeip) and '-' in str(cversion):
  put(discip, 'tojoinsw/'+name, leadernodeip)
  put(discip, 'tojoinbr/'+name, str(cversion).rsplit('-',1)[0])
 put(discip, 'tojoin/'+name,cluip)
 put(leaderip, 'allowedPartners',name)
 nameip = '_1'
 counter = 1 
 while '_1' in str(nameip):
    nameip = get(discip,'possible/'+name)[0]
    sleep(2)
    counter += 1
    if counter > 5:
        logmsg.sendlog('AddHostfa01','error',user,name)
        queuethis('AddHost','stop',user)
        return
        
 print('nameip', nameip, name)
 put(leaderip, 'ActivePartners/'+name, nameip) 
 dosync('Partnr_str_', 'sync/allowedPartners/Add_'+name+'_'+nameip+'/request','Partnr_str_'+str(stamp())) 
 dosync('Partnr_str_', 'sync/ActivePartners/Add_'+name+'_'+nameip+'/request','Partnr_str_'+str(stamp())) 
 dels(leaderip,'possible',name)
 dels(discip,'possible',name)
 queuethis('AddHost','stop',user)

if __name__=='__main__':
 data = { 'name' : 'dhcp195391', 'user':'admin' , 'leaderip': '10.11.11.100', 'myhost': 'dhcp932129' }
 do(data)
