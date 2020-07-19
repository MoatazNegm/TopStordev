#!/bin/python3.6
import subprocess,sys, datetime,socket
import json
from etcddel import etcddel as deli
from etcddellocal import etcddel as delilocal
from etcdget import etcdget as get 
from etcdputlocal import etcdput as putlocal 
from etcdput import etcdput as put 
from ast import literal_eval as mtuple
from socket import gethostname as hostname
from sendhost import sendhost
import logmsg
def setall(*bargs):
 arg=bargs
 name=bargs[-2]
 cmdline=['/TopStor/queuethis.sh','Evacuate.py','running',bargs[-1]]
 result=subprocess.run(cmdline,stdout=subprocess.PIPE)
 logmsg.sendlog('Evacuaest01','info',arg[-1],name)
 with open('/root/evacuatelocal','w') as f:
  f.write('bargs'+str(bargs)+'\n')
 myhost=socket.gethostname()
 myip=get('ready/'+myhost)
 leader=get('leader','--prefix')
 if myhost in str(leader):
  with open('/root/evacuatelocal','a') as f:
   f.write('iamleader '+myip[0]+' '+arg[-2]+'\n')
  cmdline=['/TopStor/Converttolocal.sh',myip[0]]
  result=subprocess.run(cmdline,stdout=subprocess.PIPE)
 delilocal(myip[0],'namespace','--prefix')
 delilocal(myip[0],'Active','--prefix')
 delilocal(myip[0],'alias','--prefix')
 delilocal(myip[0],'known','--prefix')
 putlocal(myip[0],'configured','no')
 with open('/root/evacuatelocal','a') as f:
  f.write('iamknown '+myip[0]+' '+arg[-2]+'\n')
  #logmsg.sendlog('Evacuaesu01','info',arg[-1],name)
 #cmdline=['/TopStor/queuethis.sh','Evacuate.py','finished',bargs[-1]]
 #result=subprocess.run(cmdline,stdout=subprocess.PIPE)
 #with open('/root/evacuatelocal','a') as f:
 # f.write('sending queue log finish '+myip[0]+' '+name+'\n')
 with open('/root/evacuatelocal','a') as f:
  f.write('rebooting '+myip[0]+' '+name+'\n')
 cmdline=['/TopStor/rebootme','finished',bargs[-1]]
 result=subprocess.run(cmdline,stdout=subprocess.PIPE)
 return 1

if __name__=='__main__':
 setall(*sys.argv[1:])
