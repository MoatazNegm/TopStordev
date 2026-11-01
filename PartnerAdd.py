#!/usr/bin/python3
import sys, subprocess
from etcdput import etcdput as put
from etcdget import etcdget as get 
from etcddel import etcddel as dels
from logmsg import sendlog, initlog
from sendhost import sendhost
from privthis import privthis 
from time import time as stamp
from secretmask import phrase_encrypt, MASK
#from replicatenow import syncpush, repliinit


def dosync(leader,sync,  *args):
  global leaderip
  dels(leaderip, 'sync',sync) 
  put(leaderip, *args)
  put(leaderip, args[0]+'/'+leader,args[1])
  return 

def initpartner(*args):
    global leader, leaderip, clusterip, myhost, myhostip
    if args[0] == 'init':
        cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py leader'
        leader=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
        cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py leaderip'
        leaderip=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
        cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py clusternode'
        myhost=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
        cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py clusternodeip'
        myhostip=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
    else:
        leader = args[0]
        leaderip = args[1]
        myhost = args[2]
        myhostip = args[3]
    clusterip = leaderip 
    initlog(clusterip, myhost)

def addpartner(*bargs):
 global leader, leaderip, clusterip, myhost, myhostip
 if myhost == leader:
    etcd = leaderip
 else:
    etcd = myhostip
 partnerip = bargs[0]
 partneralias = bargs[1].replace('_','').replace('/',':::')
 replitype = bargs[2]
 repliport = bargs[3]
 phrase = bargs[4]
 userreq = bargs[5]
 init = bargs[6]
 if (privthis(etcd,'Replication',userreq) != 'true'):
  print('not authorized to add partner')
  return
 sendlog('Partner1000','info',userreq,partneralias,replitype)
 #repliinit(leaderip,leader, etcd)
 if 'init' in init:
  # QSD5.344: the pass phrase is stored encrypted (secretmask.phrase_encrypt, 'enc~...'; QC tests 674, 704) and is no
  # longer part of the sync request key: the followers copy the whole Partner/ prefix (checksyncs 'Partnr'), the key
  # only names the request
  put(leaderip, 'Partner/'+partneralias+'_'+replitype , partnerip+'/'+replitype+'/'+str(repliport)+'/'+phrase_encrypt(partneralias, phrase)) 
  dosync(myhost,'Partnr_str_', 'sync/Partnr/Add_'+partneralias+':::'+replitype+'_'+partnerip+'::'+replitype+'::'+str(repliport)+'::x/request','Partnr_str_'+str(stamp())) 
 if 'Sender' not in replitype:
  #syncpush(partneralias+'_'+replitype,userreq) 
  put(leaderip, 'pushusers',partneralias+'/'+clusterip)
 sendlog('Partner1002','info',userreq,partneralias,replitype)
 

if __name__=='__main__':
 initpartner('init')
 with open('/root/PartnerAdd','w') as f:
    #import json
    #json.dump(sys.argv[1:], f)
    # QSD5.344: the pass phrase (argument 5) is masked in this debug copy
    f.write(' '.join(MASK if i == 5 else a for i, a in enumerate(sys.argv)))
 addpartner(*sys.argv[1:])
