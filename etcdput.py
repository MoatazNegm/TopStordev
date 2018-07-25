#!/bin/python3.6
import subprocess,sys
import json
def etcdput(key,val):
 endpoints=''
 data=json.load(open('/pacedata/runningetcdnodes.txt'));
 for x in data['members']:
  endpoints=endpoints+str(x['clientURLs'])[2:][:-2]
 cmdline=['etcdctl','-w','json','--endpoints='+endpoints,'put',key,val]
 result=subprocess.run(cmdline,stdout=subprocess.PIPE)
 #print(result)
 return 1 


if __name__=='__main__':
 etcdput(*sys.argv[1:])