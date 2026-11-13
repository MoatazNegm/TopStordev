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
 put(leaderip, 'notification',' '.join(z))
 # QC 613: a failed bus publish (pika connection error on a busy node) raised out of sendlog and aborted the caller after the
 # success notification was already shown: Hostconfig logged Unlin1012 here BEFORE encrypting and storing the new password,
 # so the user saw 'Changing password' and an internal error and the password stayed unchanged.  A notification that cannot
 # be sent must not abort the operation: the failure is reported on stdout and the work (and the log keys below) go on.
 try:
  sendhost(leaderip, str(msg),'recvreply',myhost)
 except Exception as e:
  print('sendlog: bus publish to the leader failed:', repr(e)[:120])
 for k in knowninfo:
  try:
   sendhost(k[1], str(msg),'recvreply',myhost)
  except Exception as e:
   print('sendlog: bus publish to', k[1], 'failed:', repr(e)[:120])
  knowns.append(k[1])

 stamp=datetime.datetime.now().strftime("%s%f")
 logid=f"{myhost}_{stamp}"

 put(leaderip, f"sync/log/{logid}/request", f"log_{stamp}")
 put(leaderip, f"sync/log/{logid}/request/{myhost}", f"log_{stamp}")
 put(leaderip, f"log/{logid}", " ".join(z))

if __name__=='__main__':
 initlog(getlocal('leaderip')[0], getlocal('clusternode')[0])
 sendlog(*sys.argv[1:])
