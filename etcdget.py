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
    # Used to print('not reachable') and return the string '_1' here, which
    # callers store in `result` and then access `result.stdout` on below —
    # since '_1' has no .stdout, that raised and fell into etcdget()'s own
    # except, which prints its own '_1'. Combined, shell callers doing
    # `x=\`etcdget.py ...\`` captured both lines as "not reachable _1" and
    # echoed that unquoted wherever they used $x (e.g. writing a "new IP"
    # into a config file), corrupting state instead of cleanly failing.
    # Returning None here lets etcdget()'s single except handle it, so
    # failures always come back as the one-line '_1' sentinel.
    return None
def etcdget(etcd, key, prefix=''):
 result = etcdctl(etcd, key,prefix)
 z=[]
 try:
  if(prefix =='--prefix'):
   mylist=(lambda o: (o[:-1] if o.endswith('\n') else o).split('\n') if o else [])(str(result.stdout.decode()))   # an empty value stays an (empty) line: collapsing it shifted every later key/value pair
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
   mylist=(lambda o: (o[:-1] if o.endswith('\n') else o).split('\n') if o else [])(str(result.stdout.decode()))   # an empty value stays an (empty) line: collapsing it shifted every later key/value pair
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
