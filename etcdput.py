#!/usr/bin/python3
import subprocess,sys, os
import json
from time import sleep

def etcdctl(etcd,key,prefix):
 cmdline=['/usr/local/bin/etcdctl','--user=root:YN-Password_123','--endpoints=http://'+etcd+':2379','put',key,prefix]
 cmdline=['/usr/local/bin/etcdctl','--endpoints=http://'+etcd+':2379','put',key,prefix]
 # QC 617: a failed read hands '_1' (not an address) on as the endpoint; the initial-sync loop of checksyncs.py then puts about 200
 # keys to it, and with the retries below one run took tens of minutes (the follower stopped applying sync requests).  Nothing to
 # retry against an endpoint that is not a host name or an address: fail at once, as before the retries.
 import re
 if not re.match(r'^[A-Za-z0-9][A-Za-z0-9.\-]*$', str(etcd)):
  print('not reachable')
  return
 # QC 612: one try with a 2 s limit lost the put silently (exit 0) when etcdctl was slow to start on a busy node: a new user's
 # sync request key and its password hash were missing after five adds in a row, so a follower never created the user.
 # Three tries (4 s each, 0.5 s apart, at most about 13 s)..
 for attempt in range(3):
  try:
     result=subprocess.run(cmdline,stdout=subprocess.PIPE, timeout=4)
     if result.returncode == 0:
        return result
  except Exception:
     pass
  if attempt < 2:
     sleep(0.5)
 print('not reachable')
 return




def etcdput(etcd, key,val):
 os.environ['ETCDCTL_API']= '3'
 etcdctl(etcd, key,val)
 return 1 


if __name__=='__main__':
 if len(sys.argv[1:]) != 3:
  with open('/root/etcdput_badargs.log','a') as f:
   f.write(str(sys.argv)+'\n')
 etcdput(*sys.argv[1:])
