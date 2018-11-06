#!/bin/python3.6
import subprocess,sys
import json

def etcdput(*args):
 myip=args[0]
 key=args[1]
 val=args[2]
 endpoints=''
 endpoints='http://'+myip+':2378'
 cmdline=['etcdctl','-w','json','--endpoints='+endpoints,'put',key,val]
 result=subprocess.run(cmdline,stdout=subprocess.PIPE)
 print(result)

if __name__=='__main__':
 etcdput(*sys.argv[1:])
