#!/usr/bin/python3
import subprocess,sys, datetime
import json
from etcdgetlocalpy import etcdget as getlocal
from etcdgetpy import etcdget as get
from etcdput import etcdput as put 
from ast import literal_eval as mtuple
from sendhost import sendhost

leaderip = ''
myhsot = ''
def initlog(ldr,host):
    global leaderip, myhost
    leaderip = ldr
    myhost = host

def sendlog(*args):
 global leaderip, myhost
 z=[]
 knowns=[]
 dt=datetime.datetime.now().strftime("%m/%d/%Y")
 tm=datetime.datetime.now().strftime("%H:%M:%S")
 z=['/TopStor/logmsg2.sh', dt, tm, myhost ]
 for arg in args:
  z.append(arg)
 knowninfo=get(leaderip, 'known','--prefix')
 for k in knowninfo:
  knowns.append(k[1])
 msg={'req': 'msg2', 'reply':z}
 leadername = str(get(leaderip, 'leader')[0])
 # The row is stored FIRST (log/<id> + its sync/log request): every node that does not get it live (down, returning, or a
 # send that fails) copies it from there when it catches up (pace/checksyncs.py synclogcopy).  Test 677 step 5: the node
 # events of a take over were lost, because sending to the dead old leader (still listed in ready/) raised and the row was
 # never stored.
 stamp=datetime.datetime.now().strftime("%s%f")
 logid=f"{myhost}_{stamp}"
 put(leaderip, f"log/{logid}", " ".join(z))
 put(leaderip, f"sync/log/{logid}/request", f"log_{stamp}")
 # the sender's own done mark only on the leader (it writes the row live through the cluster address); a follower that is
 # not listed ready yet (returning) did not get its own row: it copies it from log/<id> (logmsg2.sh skips a row twice)
 if myhost == leadername:
  put(leaderip, f"sync/log/{logid}/request/{myhost}", f"log_{stamp}")
 put(leaderip, 'notification',' '.join(z))
 try:
  sendhost(leaderip, str(msg),'recvreply',myhost)
 except Exception as e:
  print('log row not sent to the leader:', e)
 # test 677 step 2: the row went only to the leader and the 'known/' hosts, and known/ is empty in this cluster (addknown is
 # not run): no follower ever wrote a row, so after a take over the new leader's log had none of the rows written before.
 # Every other ready node gets it too now (the leader once, through the cluster address above).
 leadernodeip = ''.join(v for k, v in get(leaderip, 'ready/'+leadername, '--prefix') if k == 'ready/'+leadername) if leadername not in ('', '_1') else ''
 targets = []
 for k in list(knowninfo) + list(get(leaderip, 'ready', '--prefix')):
  if not isinstance(k, (tuple, list)) or len(k) < 2:
   continue
  ip = str(k[1])
  if ip in ('', '_1', leaderip, leadernodeip) or ip in targets:
   continue
  targets.append(ip)
 for ip in targets:
  try:
   sendhost(ip, str(msg),'recvreply',myhost)
   knowns.append(ip)
  except Exception as e:
   print('log row not sent to', ip, ':', e)

if __name__=='__main__':
 initlog(getlocal('leaderip')[0], getlocal('clusternode')[0])
 sendlog(*sys.argv[1:])
