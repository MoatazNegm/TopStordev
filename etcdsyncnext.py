#!/bin/python3.6
import subprocess,sys
from ast import literal_eval as mtuple
from etcdget import etcdget as get


thehost=sys.argv[1]
key=sys.argv[2]
tokey=sys.argv[3]
result=get(key,'--prefix')
print("the result",result)
if result==[]:
 print('-1')
 exit(1)
for item in result:
 x=item[0].replace('/','')
 x=x.replace(str(key),'')
 if x =='':
   adding='';
 else:
   adding='/'+x
 print('mez',thehost,tokey+adding,item[1])
 cmdline=['/pace/etcdputlocal.py',thehost, tokey+adding, item[1]]
 result=subprocess.run(cmdline,stdout=subprocess.PIPE)
