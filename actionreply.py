#!/bin/python3.6
import codecs, logmsg
import binascii
from base64 import decodestring as decode
from ast import literal_eval as mtuple
from etcdget import etcdget as get
import subprocess, socket
import logmsg
def do(body):
 myhost=socket.gethostname()
 z=[]
 with open('/root/recv','w') as f:
  f.write('Recevied a reply:'+str(body[2:][:-1])+'\n')
 y=body[2:][:-1].replace('\\','').replace("'{",'"{').replace("}'",'}"').replace('"b\'',"'b;").replace('\n','').replace('"]','\\"]')
 t=mtuple(y)
 yy=t['req'].replace("'b;",'"b\'')
 with open('/root/recv','w') as f:
  f.write('Recevied a reply:'+yy+'\n')
 r=mtuple(yy) 
 with open('/root/recv','a') as f:
  f.write('tis:'+'found'+'\n')
 with open('/root/recv','a') as f:
   f.write('Request details:'+r['req']+'\n')
########## if user ######################
 if r["req"]=='user':
  logmsg.sendlog('Unlin1005', 'info', 'system')
  with open('/etc/passwd') as f:
   revf=f.readlines()
   for line in revf:
    if 'TopStor' in line:
     l=line.split(':')
     with open('/root/recv','a') as f:
      f.write('syncing user: '+l[0]+'\n')
     cmdline=['/TopStor/UnixDelUser_sync',l[0], 'system']
     result=subprocess.run(cmdline,stdout=subprocess.PIPE)
  with open('/root/recv','a') as f:
   f.write('Syncing users:\n')
  for x in r["reply"]:
   cmdline=['/TopStor/UnixAddUser_sync',x[0],x[2],x[1]]
   with open('/root/recv','a') as f:
    f.write('adding user '+str(cmdline)+'\n')
   cmdline=['/TopStor/UnixAddUser_sync',x[0],x[2],x[1]]
   result=subprocess.run(cmdline,stdout=subprocess.PIPE)
  logmsg.sendlog('Unlin1006', 'info', 'system')
########## if group######################
 if r["req"]=='group':
  logmsg.sendlog('Unlin1105', 'info', 'system')
  with open('/etc/passwd') as f:
   revf=f.readlines()
   for line in revf:
    if 'Group' in line:
     l=line.split(':')
     with open('/root/recv','a') as f:
      f.write('syncing Groups: '+l[0]+'\n')
     cmdline=['/TopStor/UnixDelGroup_sync',l[0], 'system']
     result=subprocess.run(cmdline,stdout=subprocess.PIPE)
  with open('/root/recv','a') as f:
   f.write('Syncing Groups:\n')
  for x in r["reply"]:
   cmdline=['/TopStor/UnixAddGroup_sync',x[0],x[2],x[1]]
   with open('/root/recv','a') as f:
    f.write('adding Group '+str(cmdline)+'\n')
   cmdline=['/TopStor/UnixAddGroup_sync',x[0],x[2],x[1]]
   result=subprocess.run(cmdline,stdout=subprocess.PIPE)
  logmsg.sendlog('Unlin1106', 'info', 'system')
########## if cifs ######################
 elif r["req"]=='cifs':
  logmsg.sendlog('Actst1000', 'info', 'system')
  with open('/root/recv','a') as f:
   f.write('preparing cifs:'+str(r["reply"][0])+'\n')
  cifsconf=codecs.decode(r["reply"][0],'hex')
  cifsconf=cifsconf.decode('utf-8')
  with open('/root/recv','a') as f:
   f.write('cifs conf: '+cifsconf+'\n')
  with open('/etc/samba/smb.conf','w') as f:
   f.write(cifsconf)
  logmsg.sendlog('Actsu1000', 'info', 'system')
########## if logall ######################
 elif r["req"]=='logall':
  logmsg.sendlog('Actst1001', 'info', 'system')
  with open('/root/recvlogall','w') as f:
   f.write('preparing logs:\n')
  conf=codecs.decode(r["reply"][0],'hex')
  conf=conf.decode('utf-8')
  with open('/root/recvlogall','a') as f:
   f.write('logs: '+conf+'\n')
  with open('/var/www/html/des20/Data/TopStorglobal.log','w') as f:
   f.write(conf)
  logmsg.sendlog('Actsu1001', 'info', 'system')
########## if msg ###############
 elif r["req"]=='msg':  
  with open('/root/recv','a') as f:
   f.write('received msg from parnter :'+str(r["reply"])+'\n')
   f.write('type of message :'+str(type(r["reply"]))+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if queue ###############
 elif r["req"]=='queue':  
  with open('/root/recv','a') as f:
   f.write('received queue from parnter :'+str(r["reply"])+'\n')
   f.write('type of message :'+str(type(r["reply"]))+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if evacuate ###############
 elif r["req"]=='Evacuate':  
  with open('/root/recv','a') as f:
   f.write('received evacuate from parnter :'+str(r["reply"])+'\n')
   f.write('type of message :'+str(type(r["reply"]))+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if msg2 ###############
 elif r["req"]=='msg2':  
  with open('/root/recv','a') as f:
   f.write('received msg2 from parnter :'+str(r["reply"])+'\n')
   f.write('type of message :'+str(type(r["reply"]))+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if DGsetPool ###############
 elif r["req"]=='DGsetPool':  
  with open('/root/recv','a') as f:
   f.write('received DGsetPool from parnter :'+str(r["reply"])+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if SnapshotRolback ###############
 elif r["req"]=='SnapshotRollback':  
  with open('/root/recv','a') as f:
   f.write('received SnapshotRollback from parnter :'+str(r["reply"])+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if PeriodManage ###############
 elif r["req"]=='PeriodManage':  
  with open('/root/recvperiod','w') as f:
   f.write('received PeriodManage from parnter :'+str(r["reply"])+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if SnapshotDelete ###############
 elif r["req"]=='SnapshotDelete':  
  with open('/root/recv','a') as f:
   f.write('received SnapshotDelete from parnter :'+str(r["reply"])+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if SnapshotCreate ###############
 elif r["req"]=='SnapshotCreate':  
  with open('/root/recv','a') as f:
   f.write('received SnapshotCreate from parnter :'+str(r["reply"])+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if VolumeChange ###############
 elif r["req"]=='VolumeChange':  
  with open('/root/recvVolumeChange','w') as f:
   f.write('received VolumeChange from parnter :'+str(r["reply"])+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if VolumeCreate ###############
 elif r["req"]=='VolumeCreate':  
  with open('/root/recvVlumeCreate','a') as f:
   f.write('received VolumeCreate from parnter :'+str(r["reply"])+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if VolumeDelete ##############
 elif r["req"]=='VolumeDelete':  
  with open('/root/recv','a') as f:
   f.write('received VolumeDelete from parnter :'+str(r["reply"])+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if Zpool (direct command..etc) ##############
 elif r["req"]=='Zpool':  
  with open('/root/recv','a') as f:
   f.write('received Zpool from parnter :'+str(r["reply"])+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if Zpoolimport (import) ##############
 elif r["req"]=='Zpoolimport':  
  pool=r["reply"][4].split('/')[2]
  logmsg.sendlog('Zpst02','info','system',pool)
  with open('/root/recv','a') as f:
   f.write('received Zpool from parnter :'+str(r["reply"])+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if clear cache ##############
 elif r["req"]=='ClearCache':  
  with open('/root/recv','a') as f:
   f.write('received ClearCache from parnter :'+str(r["reply"])+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if synchosts ##############
 elif r["req"]=='SyncHosts':  
  with open('/root/recv','a') as f:
   f.write('received synchosts from parnter :'+str(r["reply"])+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if broadcast ##############
 elif r["req"]=='broadcast':  
  with open('/root/recv','a') as f:
   f.write('received broadcast from parnter :'+str(r["reply"])+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if Movecache ##############
 elif r["req"]=='Movecache' and t["host"] != myhost:  
  with open('/root/recv','a') as f:
   f.write('received cachemove from partner :'+'\n')
  cachename=r["reply"][0]
  with open('/root/recv','a') as f:
   f.write('cachename:'+cachename+'\n')
  cachefileenc=r["reply"][1]
  #cachefile=decode(cachefileenc)
  #cachefile=binascii.unhexlify(cachefileenc)
  #with open(cachename,'wb') as f:
  # f.write(cachefile)
########## if HostManualconfig ##############
 elif r["req"]=='LocalManualConfig':  
  with open('/root/recv2','a') as f:
   f.write('received LocalManualConfig from parnter :'+str(r["reply"])+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if HostgetIPs ##############
 elif r["req"]=='HostgetIPs':  
  with open('/root/recv2','a') as f:
   f.write('received HostgetIPs from parnter :'+str(r["reply"])+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if ReleasePoolLock ##############
 elif r["req"]=='ReleasePoolLock':  
  with open('/root/recv2','a') as f:
   f.write('received ReleasePoolLock from parnter :'+str(r["reply"])+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if GroupChange ##############
 elif r["req"]=='RemoveTargets':  
  with open('/root/recvtmp2','w') as f:
   f.write('received RemoveTarget from parnter :'+str(r["reply"])+'\n')
  torun=['/pace/removetargetdisks.sh',r["reply"][0]]
  with open('/root/recvtmp2','a') as f:
   f.write('received RemoveTarget from parnter :'+str(torun)+'\n')
  result=subprocess.run(torun,stdout=subprocess.PIPE)
########## if GroupChange ##############
 elif r["req"]=='GroupChange':  
  with open('/root/recv2','a') as f:
   f.write('received GroupChange from parnter :'+str(r["reply"])+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if UserChange ##############
 elif r["req"]=='UserChange':  
  with open('/root/recv2','a') as f:
   f.write('received UserChange from parnter :'+str(r["reply"])+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if UserAdd ##############
 elif r["req"]=='UserAdd':  
  with open('/root/recv2','a') as f:
   f.write('received UserAdd from parnter :'+str(r["reply"])+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if UserDel ##############
 elif r["req"]=='UserDel':  
  with open('/root/recv2','a') as f:
   f.write('received UserDel from parnter :'+str(r["reply"])+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if GroupAdd ##############
 elif r["req"]=='GroupAdd':  
  with open('/root/recv2','a') as f:
   f.write('received GroupAdd from parnter :'+str(r["reply"])+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if GroupDel ##############
 elif r["req"]=='GroupDel':  
  with open('/root/recv2','a') as f:
   f.write('received GroupDel from parnter :'+str(r["reply"])+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if NTP  ##############
 elif r["req"]=='HostManualConfigNTP':  
  with open('/root/recv2','a') as f:
   f.write('received HostManualConfigNTP from parnter :'+str(r["reply"])+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
 ########## if TZ  ##############
 elif r["req"]=='HostManualConfigTZ':  
  with open('/root/recv2','a') as f:
   f.write('received HostManualConfigTZ from parnter :'+str(r["reply"])+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
  ########## if GW  ##############
 elif r["req"]=='HostManualConfigGW':  
  with open('/root/recv2','a') as f:
   f.write('received HostManualConfigGW from parnter :'+str(r["reply"])+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
 ########## if UpdateHosts  ##############
 elif r["req"]=='UpdateHosts':  
  with open('/root/recv2','a') as f:
   f.write('received UpdateHosts from parnter :'+str(r["reply"])+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
 


if __name__=='__main__':
 import sys
 msg=str({'host': 'localhost', 'req': sys.argv[1]})
 do('b"'+msg+'"') 
 exit()
