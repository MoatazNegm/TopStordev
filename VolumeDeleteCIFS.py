#!/usr/bin/python3
import sys, datetime
from logqueue import queuethis
import json
from etcdgetpy import etcdget as get
from ast import literal_eval as mtuple
from socket import gethostname as hostname
from sendhost import sendhost
def send(*bargs):
 if(len(bargs) < 3):
  args=bargs[0].split()
 else:
  args=bargs
 pool=args[0]
 pool=str(pool)
 z=[]
 with open('/root/VolumeDelete','w') as f:
  f.write('pool='+pool+'\n')
 owner=args[-2]
 with open('/root/VolumeDelete','a') as f:
  f.write('owner='+owner+'\n')
 myhost=hostname()
 with open('/root/VolumeDelete','a') as f:
  f.write('myhost='+myhost+'\n')
 ownerip=get('leader',owner)
 if ownerip[0]== -1:
  ownerip=get('known',owner)
  if ownerip[0]== -1:
   return 3
 z=['/TopStor/pump.sh','VolumeDeleteCIFS']
 for arg in args[:-2]:
  z.append(arg)
 msg={'req': 'VolumeDelete', 'reply':z}
 with open('/root/VolumeDelete','a') as f:
  f.write('myhost='+ownerip[0][1]+' '+myhost+' '+str(z)+'\n')
 sendhost(ownerip[0][1], str(msg),'recvreply',myhost)
 return 1

if __name__=='__main__':
 send(*sys.argv[1:])
