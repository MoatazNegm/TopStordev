#!/bin/python3.6
import subprocess,sys, datetime
from etcdget import etcdget as get
from etcdput import etcdput as put
from broadcasttolocal import broadcasttolocal
from ast import literal_eval as mtuple
import logmsg
def config(*bargs):
 cmdline=['/TopStor/queuethis.sh','LocalManualconfig.py','running',bargs[-1]]
 result=subprocess.run(cmdline,stdout=subprocess.PIPE)
 enpdev='eno1'
 needreboot=False
 with open('/root/HostManualconfigtmp3','w') as f:
  f.write(str(bargs))
 with open('/TopStordata/Hostprop.txt') as f:
  oldbarg=f.read()
 oldbarg=oldbarg.replace('"','').replace('{','').replace('}','').replace(',',' ')
 oldarg=oldbarg.split()
 arg=bargs
 with open('/root/HostManualconfigtmp2','w') as f:
  f.write('arg:'+str(arg)+'\n')
 with open('/root/HostManualconfigtmp2','a') as f:
  f.write('oldarg:'+str(oldarg)+'\n')
 change={}
 owner=''
 msg={}
 setarg=set(arg[:-1])
 setold=set(oldarg)
 diff=setarg-setold
 print(diff)
 newchange=list(diff) 
 print(newchange)
 for x in newchange:
  kvx=x.split(':')
  change[kvx[0]]=kvx[1]
  for y in oldarg:
   kvy=y.split(':')
   if kvy[0]==kvx[0]:
    change['old'+kvy[0]]=kvy[1]
 
 if len(change) < 1: 
  return
 logmsg.sendlog('HostManual1002','info',arg[-1])
 with open('/root/HostManualconfigtmp2','a') as f:
  f.write('change:'+str(change)+'\n')
 '''
 change = {'tz': 'Kuw@@(GMT+03!00)_Kuwait@_Riyadh@_Baghdad', 'oldtz': '@@_Africa/Cairo_(EET@_+0200)', 'name': 'stor11', 'oldname': 'stor0', 'mgmtip': '192.168.9.12', 'oldmgmtip': '192.168.8.24', 'ntp': '1.asia.pool.ntp.org', 'oldntp': '0.asia.pool.ntp.org'}
 '''
######### changing name ###############
 if 'name' in change:
  logmsg.sendlog('HostManual1st5','info',arg[-1],change['oldname'],change['name'])
  for x in oldarg:
   if 'hostname:' in x:
    owner=x.split(':')[1]
    break
  put('alias/'+owner,change['name'])
  broadcasttolocal('alias/'+owner,change['name'])
  logmsg.sendlog('HostManual1su5','info',arg[-1],change['oldname'],change['name'])
######### changing cluster address ###############
 if 'mgmtip' in change:
  print('############### found cluster address')
  if 'mgmtsubnet' in change:
   subnet=change['mgmtsubnet']
   oldsubnet=change['oldmgmtsubnet']
  else:
   subnet=oldsubnet=24
   for y in oldarg:
    if 'mgmtsubnet' in y:
     y=y.split(':')
     subnet=oldsubnet=y[1]
  logmsg.sendlog('HostManual1st7','info',arg[-1],change['oldmgmtip']+'/'+oldsubnet,change['mgmtip']+'/'+subnet)
  with open('/root/HostManualconfigtmp2','a') as f:
   f.write('run HostManualconfigNameSpace:'+change['mgmtip']+change['oldmgmtip']+subnet+oldsubnet+'\n')
  cmdline=['/TopStor/HostManualconfigNameSpace',change['mgmtip'],change['oldmgmtip'],subnet,oldsubnet]
  result=subprocess.run(cmdline,stdout=subprocess.PIPE)
  put('namespace/mgmtip',change['mgmtip']+'/'+subnet)
  broadcasttolocal('namespace/mgmtip',change['mgmtip']+'/'+subnet)
  logmsg.sendlog('HostManual1su7','info',arg[-1],change['oldmgmtip']+'/'+oldsubnet,change['mgmtip']+'/'+subnet)
######## changing data address ###############
 if 'dataip' in change:
  if 'dataipsubnet' in change:
   subnet=change['dataipsubnet']
   oldsubnet=change['olddataipsubnet']
  else:
   subnet=oldsubnet=24
   for y in oldarg:
    if 'dataipsubnet' in y:
     y=y.split(':')
     subnet=oldsubnet=y[1]
  logmsg.sendlog('HostManual1st8','info',arg[-1],change['olddataip']+'/'+oldsubnet,change['dataip']+'/'+subnet)
  cmdline=['/TopStor/HostManualconfigDataIP',change['dataip'],change['olddataip'],subnet,oldsubnet]
  result=subprocess.run(cmdline,stdout=subprocess.PIPE)
  logmsg.sendlog('HostManual1su8','info',arg[-1],change['olddataip']+'/'+oldsubnet,change['dataip']+'/'+subnet)
########## changing ntp server ###############
 if 'ntp' in change:
  logmsg.sendlog('HostManual1st9','info',arg[-1],change['oldntp'],change['ntp'])
  cmdline=['/TopStor/HostManualconfigNTP.py',change['ntp']]
  result=subprocess.run(cmdline,stdout=subprocess.PIPE)
  logmsg.sendlog('HostManual1su9','info',arg[-1],change['oldntp'],change['ntp'])
########### changing time zone ###############
 if 'tz' in change:
  logmsg.sendlog('HostManual1st10','info',arg[-1],change['oldtz'],change['tz'])
  cmdline=['/TopStor/HostManualconfigTZ.py',change['tz']]
  result=subprocess.run(cmdline,stdout=subprocess.PIPE)
  logmsg.sendlog('HostManual1su10','info',arg[-1],change['oldtz'],change['tz'])
############ changing gateway  ###############
 if 'gw' in change:
  logmsg.sendlog('HostManual1st11','info',arg[-1],change['oldgw'],change['gw'])
  cmdline=['/TopStor/HostManualconfigGW.py',change['gw']]
  result=subprocess.run(cmdline,stdout=subprocess.PIPE)
  logmsg.sendlog('HostManual1su11','info',arg[-1],change['oldgw'],change['gw'])
 ############ changing configured  ###############
 if 'configured' in change:
  if 'yes' in change['configured']:
   logmsg.sendlog('HostManual1st12','info',arg[-1])
  else:
   logmsg.sendlog('HostManual2st12','info',arg[-1])
   
  cmdline=['/TopStor/HostManualconfigCF',change['configured']]
  result=subprocess.run(cmdline,stdout=subprocess.PIPE)
  if 'yes' in change['configured']:
   logmsg.sendlog('HostManual1su12','info',arg[-1])
  else:
   logmsg.sendlog('HostManual2su12','info',arg[-1])
  needreboot=True
 ######### changing box address ###############
 if 'addr' in change:
  if 'addrsubnet' in change:
   subnet=change['addrsubnet']
   oldsubnet=change['oldaddrsubnet']
  else:
   subnet=oldsubnet=24
   for y in oldarg:
    if 'addrsubnet' in y:
     y=y.split(':')
     subnet=oldsubnet=y[1]
  with open('/root/HostManualconfigtmp2','a') as f:
   f.write('/will/change box address)\n');
  logmsg.sendlog('HostManual1st6','info',arg[-1],change['oldaddr']+'/'+oldsubnet,change['addr']+'/'+subnet)
  cmdline=['/TopStor/HostManualconfigCC',change['addr'],change['oldaddr'],subnet,oldsubnet]
  result=subprocess.run(cmdline,stdout=subprocess.PIPE)
  #cmdline=['/TopStor/rebootme',change['addr'],change['oldaddr'],subnet,oldsubnet]
  #result=subprocess.run(cmdline,stdout=subprocess.PIPE)
  logmsg.sendlog('HostManual1su6','info',arg[-1],change['oldaddr']+'/'+oldsubnet,change['addr']+'/'+subnet)
  needreboot=True
####################################################
# cmdline=['/TopStor/HostgetIPs']
 cmdline=['/TopStor/queuethis.sh','LocalManualconfig.py','finished',bargs[-1]]
 result=subprocess.run(cmdline,stdout=subprocess.PIPE)
 if needreboot:
  cmdline=['/TopStor/rebootme','now']
  result=subprocess.run(cmdline,stdout=subprocess.PIPE)
  
 return 1

if __name__=='__main__':
 config(*sys.argv[1:])
