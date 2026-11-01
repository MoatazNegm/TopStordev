#!/usr/bin/python3
import sys
from time import time as timestamp
from secrets import token_hex
from etcdgetpy import etcdget as get
from etcdput import etcdput as put 
from time import time as timestamp
import subprocess

def setlogin(leaderip,myhost, user,passw,token=0):
 
 with open('/TopStordata/chkuser','w') as f:
  f.write(" ".join([leaderip,myhost, user,'****',str(token),'\n']))     # QSD5.344: never the login password (validator M2)
 if len(str(token)) < 2:
  oldpass = str(get(leaderip, 'usershash/'+user)[0])
  if len(oldpass) < 3:
      return({},0)
  cmdline='/TopStor/decthis.sh '+user+' '+oldpass
  pass1=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode().split('_result')[1]
  if passw != pass1 and user=='admin':
   with open('/TopStordata/initstamp','r') as f:
    initstamp = f.read()
   if float(timestamp()) - 330. < float(initstamp):
    oldpass = str(get(leaderip, 'usershashadm/'+user)[0]).replace('\n','')
    cmdline='/TopStor/decthis.sh '+user+' '+oldpass
    pass1=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode().split('_result')[1]
  if passw != pass1:
        return ({},0)
  token = token_hex(16)
 stamp = int(timestamp() + 3600)
 put(leaderip, 'login/'+user,token+'/'+str(stamp))
 userdict = {'user':user, 'timestamp':stamp}
 print(userdict,token)
 return (userdict, token)
 

if __name__=='__main__':
 setlogin(*sys.argv[1:])
