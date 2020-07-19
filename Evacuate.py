#!/bin/python3.6
import subprocess,sys, datetime
import json
from etcdget import etcdget as get
from etcdput import etcdput as put 
from etcddel import etcddel as deli 
from ast import literal_eval as mtuple
from socket import gethostname as hostname
from sendhost import sendhost
from time import sleep
def sendlog(*args):
 z=[]
 knowns=[]
 myhost=hostname()
 z=['/TopStor/Evacuatelocal.py']
 with open('/root/evacuate','w') as f:
  f.write('bargs'+str(args)+'\n')
 for arg in args:
  z.append(arg)
 msg={'req': 'Evacuate', 'reply':z}
 hostip=get('ActivePartners/'+args[-2])
 losts=get('lost','--prefix')
 knowns=get('knwon','--prefix')
 readys=get('ready','--prefix')
 if args[-2] not in str(losts) or args[-2] in str(readys):
  sendhost(hostip[0], str(msg),'recvreply',myhost)
 isleader=1
 leader=get('leader','--prefix')
 if args[-2] in str(leader):
  isleader=1
  nextleader=get('nextlead')[0].split('/')[0]
  while isleader:
   print('still leader')
   sleep(2)
   leader=get('leader','--prefix')
   if nextleader in str(leader):
    isleader=0
 deli("",args[-2])
 put("tosync","yes")

if __name__=='__main__':
 sendlog(*sys.argv[1:])
