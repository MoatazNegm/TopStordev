#!/bin/python3.6
import subprocess,sys, os
import json
from ast import literal_eval as mtuple
def space(*args):
 os.environ['ETCDCTL_API']= '3'
 endpoints=''
 data=json.load(open('/pacedata/runningetcdnodes.txt'));
 for x in data['members']:
  endpoints=endpoints+str(x['clientURLs'])[2:][:-2]+','
 endpoints = endpoints[:-1]
 cmdline=['/bin/etcdctl','--user=root:YN-Password_123','--endpoints='+endpoints,'--write-out=table','endpoint','status']
 result=subprocess.run(cmdline,stdout=subprocess.PIPE).stdout.decode('utf-8')
 print(result)
 cmdline=['/bin/etcdctl','--user=root:YN-Password_123','--endpoints='+endpoints,'--write-out=json','endpoint','status']
 result=subprocess.run(cmdline,stdout=subprocess.PIPE).stdout.decode('utf-8')
 res = mtuple(result)[0]
 print(res['Status']['header']['revision'])
 cmdline=['/bin/etcdctl','--user=root:YN-Password_123','--endpoints='+endpoints,'compact',str(res['Status']['header']['revision'])]
 result=subprocess.run(cmdline,stdout=subprocess.PIPE).stdout.decode('utf-8')
 print(result)
 cmdline=['/bin/etcdctl','--user=root:YN-Password_123','--endpoints='+endpoints,'defrag']
 result=subprocess.run(cmdline,stdout=subprocess.PIPE).stdout.decode('utf-8')
 print(result)
 cmdline=['/bin/etcdctl','--user=root:YN-Password_123','--endpoints='+endpoints,'--write-out=table','endpoint','status']
 result=subprocess.run(cmdline,stdout=subprocess.PIPE).stdout.decode('utf-8')
 print(result)
 
if __name__=='__main__':
 space(*sys.argv[1:])
