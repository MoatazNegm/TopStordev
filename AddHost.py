#!/bin/python3.6
import subprocess,sys, datetime,socket
import json
from etcdput import etcdput as put 
import logmsg
def setall(*bargs):
 arg=bargs
 name=bargs[-2]
 cmdline=['/TopStor/queuethis.sh','AddHost.py','running',bargs[-1]]
 result=subprocess.run(cmdline,stdout=subprocess.PIPE)
 logmsg.sendlog('AddHostst01','info',arg[-1],name)
 put('allowedPartners',name)

if __name__=='__main__':
 setall(*sys.argv[1:])
