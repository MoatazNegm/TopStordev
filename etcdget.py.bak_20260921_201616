#!/usr/bin/python3
import subprocess,sys, os
import json
from time import sleep
from checkleader import checkleader

dev = 'enp0s8'
os.environ['ETCDCTL_API']= '3'

def etcdctl(etcd, key,prefix):
 cmdline=['etcdctl','--user=root:YN-Password_123','--endpoints=http://'+etcd+':2379','get',key,prefix]
 cmdline=['etcdctl','--endpoints=http://'+etcd+':2379','get',key,prefix]
 #print(' '.join(cmdline))
 try:
    result=subprocess.run(cmdline,stdout=subprocess.PIPE, timeout=2)
    return result 
 except:
    print('not reachable')
    return '_1' 
def etcdget(etcd, key, prefix=''):
 result = etcdctl(etcd, key,prefix)
 z=[]
 try:
  if(prefix =='--prefix'):
   mylist=str(result.stdout.decode()).replace('\n\n','\n').split('\n')
   zipped=zip(mylist[0::2],mylist[1::2])
   for x in zipped:
    z.append(x) 
    print(x)
  elif(prefix == ''):
   if len(str(result.stdout).split(key)) > 2 :	
    z.append(key.join(str(result.stdout).split(key)[1:])[2:][:-3])
   else:
    z.append((str(result.stdout).split(key)[1][2:][:-3]))
   print(z[0])
  else:
   result = etcdctl(etcd,key,'--prefix')
   mylist=str(result.stdout.decode()).replace('\n\n','\n').split('\n')
   zipped=zip(mylist[0::2],mylist[1::2])
   for x in zipped:
    if prefix in str(x):
     z.append(x)
     print(x)
   if(len(z) == 0):
     z.append('_1')
     print('_1')
 except:
  z.append('_1')
  print('_1')
 return z
if __name__=='__main__':
 etcdget(*sys.argv[1:])
