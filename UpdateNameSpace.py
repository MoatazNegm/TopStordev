#!/bin/python3.6
import subprocess,sys
from etcdget import etcdget as get
from etcdput import etcdput as put 
import json
dev='eno1'
def updatenamespace(*args):
  put('namespace/mgmtip',args[0])
  print('hihi',args[0])
  print('hi',args[0].split('/')[0],args[0].split('/')[1])
  print('hihihi',args[1].split('/')[0],args[1].split('/')[1])
  cmdline='/sbin/pcs resource update mgmtip ip='+args[0].split('/')[0]+' cidr_netmask='+args[0].split('/')[1]
  subprocess.run(cmdline.split(),stdout=subprocess.PIPE)
  cmdline='/sbin/ip addr del '+args[1].split('/')[0]+' dev '+dev
  subprocess.run(cmdline.split(),stdout=subprocess.PIPE)
  
if __name__=='__main__':
 updatenamespace(*sys.argv[1:])
