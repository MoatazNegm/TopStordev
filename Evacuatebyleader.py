#!/usr/bin/python3
import subprocess,sys, datetime
from logqueue import queuethis, initqueue
from etcdput import etcdput as put 
from time import sleep
from etcdget import etcdget as get
from etcddel import etcddel as deli 
import logmsg


def setall(*bargs):
 myhost = bargs[1] 
 leaderip = bargs[0] 
 initqueue(leaderip, myhost)
 logmsg.initlog(leaderip, myhost)
 myhostip = get(leaderip, 'ready/'+myhost)[0] 
 hostn=bargs[2]
 hostip=bargs[3]
 userreq=bargs[-1]
 print('hihih',hostip, hostn)
 leader=get(leaderip, 'leader')[0]
 print('iiiiiiiiiiiiiiiii',hostn,myhost, leader, hostip)
 print('iam here', hostn, hostip)
 cmdline=['/pace/removetargetdisks.sh', hostn, hostip]
 result=subprocess.run(cmdline,stdout=subprocess.PIPE)
 cmdline=['/pace/hostlost.sh',leader, leaderip, myhost, myhostip, hostn]
 result=subprocess.run(cmdline,stdout=subprocess.PIPE)
 deli(leaderip, "",hostn)
 logmsg.sendlog('Evacuaesu01','info',userreq ,hostn)
 return

if __name__=='__main__':
 setall(*sys.argv[1:])
