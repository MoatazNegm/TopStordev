#!/bin/python3.6
import subprocess,sys, datetime
import json
from etcdget import etcdget as get
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
 if args[-2] not in str(losts):
  sendhost(hostip[0], str(msg),'recvreply',myhost)
  sleep(60)
 deli("",args[-2])
 put("tosync","yes")

if __name__=='__main__':
 sendlog(*sys.argv[1:])
