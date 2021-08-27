#!/bin/python3.6
import subprocess,sys
from etcdget import etcdget as get
import json
enpdev='eno1'
def cleardataip(*args):
	nslist=get('volumes','CIFS')
	for x in nslist:
		params=x[1].split('/')
		cmdline='/sbin/ip addr del '+params[7]+'/'+params[8]+' dev '+$enpdev 
		subprocess.run(cmdline.split(),stdout=subprocess.PIPE)
	nslist=get('volumes','NFS')
	for x in nslist:
		params=x[1].split('/')
		cmdline='/sbin/ip addr del '+params[9]+'/'+params[10]+' dev '+$enpdev 
		subprocess.run(cmdline.split(),stdout=subprocess.PIPE)
if __name__=='__main__':
 cleardataip(*sys.argv[1:])
