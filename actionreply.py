#!/usr/bin/python3
import codecs, logmsg
import binascii
from base64 import decodebytes as decode
#from base64 import decodestring as decode
from ast import literal_eval as mtuple
import subprocess, socket
from logqueueheap import heapthis, syncnextlead
from syncq import syncq 
from secretmask import bus_log_text, bus_log_reply

archive = 1 

def do(leader, leaderip, myhost, myip, etcdip, body):
 global archive
 logmsg.initlog(leaderip, myhost)
 z=[]
 r=mtuple(body.replace("'",'"'))
 # QSD5.347: what is printed or written of a message has its secrets masked (secretmask.bus_log_text / bus_log_reply:
 # the sender's masked copy 'logreply', then the fixed list of secret arguments).  The clear UnixAddUser password (and
 # every other secret on a command line) stayed in /root/recv, /root/recvpump ... (QSD5.346 proof, QX-221 step 4).
 # The commands below still run r["reply"], the real values.
 try:
  logbody = bus_log_text(body)
  rlog = bus_log_reply(r)
 except Exception:
  logbody, rlog = '<message not shown>', '<reply not shown>'
 print('body',logbody)
 with open('/root/recv','a') as f:
  f.write('Recevied a body:'+logbody+'\n')
 print('############################3')
 with open('/root/recv', 'r') as f:
        lines = f.readlines()
 if len(lines) > 30:
        # Keep only the last 30 lines
        with open('/root/recv', 'w') as f:
            f.writelines(lines[-15:])

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
  with open('/TopStordata/TopStorglobal.log','w') as f:
   f.write(conf)
  logmsg.sendlog('Actsu1001', 'info', 'system')
########## if msg ###############
 elif r["req"]=='msg':  
  with open('/root/recv','a') as f:
   f.write('received msg from parnter :'+str(rlog)+'\n')
   f.write('type of message :'+str(type(r["reply"]))+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########### if Pumpthis ###############
 elif r["req"]=='Pumpthis':  
  with open('/root/recvpump','w') as f:
   f.write('received a pump from parnter :'+str(rlog)+'\n')
   f.write('type of message :'+str(type(r["reply"]))+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########### if synq ###############
 elif r["req"]=='synq':  
  with open('/root/recv','a') as f:
   f.write('received msg from parnter :'+str(rlog)+'\n')
   f.write('type of message :'+str(type(r["reply"]))+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if taskperf ###############
 elif r["req"]=='taskperf':  
   with open('/root/recvtaskperf','w') as f:
    f.write('received queue from parnter :'+str(rlog)+'\n')
    f.write('type of message :'+str(type(r["reply"]))+'\n')
   with open('/TopStordata/taskperf','a') as f:
    f.write(r["reply"][-1][:-1].replace('ndhcp','\ndhcp')+'\n')
    print('wirtten archive')
   #cmdline=['/sbin/logrotate','logqueue.cfg','-f']
   #subprocess.run(cmdline,stdout=subprocess.PIPE)
   syncq(leader,myhost,archive)
   if archive:
    archive = 0
########## if queue ###############
 elif r["req"]=='queue':  
  with open('/root/recvqueue','w') as f:
   f.write('received queue from parnter :'+str(rlog)+'\n')
   f.write('type of message :'+str(type(r["reply"]))+'\n')
  heapthis(leaderip, myhost, r["reply"][1:])
########## if evacuate ###############
 elif r["req"]=='Evacuate':  
  with open('/root/recv','a') as f:
   f.write('received evacuate from parnter :'+str(rlog)+'\n')
   f.write('type of message :'+str(type(r["reply"]))+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if msg2 ###############
 elif r["req"]=='msg2':  
  with open('/root/recv','a') as f:
   f.write('received msg2 from parnter :'+str(rlog)+'\n')
   f.write('type of message :'+str(type(r["reply"]))+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if UserPass ###############
 elif r["req"]=='UserPassChange':  
  with open('/root/recv','a') as f:
   f.write('received user password from parnter :'+str(rlog)+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if DGsetPool ###############
 elif r["req"]=='DGsetPool':  
  with open('/root/recv','a') as f:
   f.write('received DGsetPool from parnter :'+str(rlog)+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if SnapshotRolback ###############
 elif r["req"]=='SnapshotRollback':  
  with open('/root/recv','a') as f:
   f.write('received SnapshotRollback from parnter :'+str(rlog)+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if PeriodManage ###############
 elif r["req"]=='PeriodManage':  
  with open('/root/recvperiod','w') as f:
   f.write('received PeriodManage from parnter :'+str(rlog)+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if SnapshotDelete ###############
 elif r["req"]=='SnapshotDelete':  
  with open('/root/recv','a') as f:
   f.write('received SnapshotDelete from parnter :'+str(rlog)+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if syncq ###############
 elif r["req"]=='syncq':  
  with open('/root/recvsyncq','w') as f:
   f.write('recieved request to sync:'+str(r["reply"]))
  syncnextlead(leaderip, myhost, r["reply"][0],r["reply"][1])
########## if syncthisfile ###############
 elif r["req"]=='syncthisfile':  
  with open('/root/recvsyncthis','a') as f:
   f.write('receivee here file from parnter :'+str(r["reply"][0])+'\n')
  print(r["reply"][0])
  print(r["reply"][1].replace('ndhcp','\ndhcp')+'\n')
  with open(r["reply"][0],'w') as f:
   f.write(r["reply"][1].replace('ndhcp','\ndhcp')+'\n')
########## if SnapshotCreate ###############
 elif r["req"]=='SnapshotCreate':  
  with open('/root/recv','a') as f:
   f.write('received SnapshotCreate from parnter :'+str(rlog)+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if VolumeChange ###############
 elif r["req"]=='VolumeChange':  
  with open('/root/recvVolumeChange','w') as f:
   f.write('received VolumeChange from parnter :'+str(rlog)+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if VolumeCreate ###############
 elif r["req"]=='VolumeCreate':  
  with open('/root/recvVlumeCreate','a') as f:
   f.write('received VolumeCreate from parnter :'+str(rlog)+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if VolumeDelete ##############
 elif r["req"]=='VolumeDelete':  
  with open('/root/recv','a') as f:
   f.write('received VolumeDelete from parnter :'+str(rlog)+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if Zpool (direct command..etc) ##############
 elif r["req"]=='Zpool':  
  with open('/root/recv','a') as f:
   f.write('received Zpool from parnter :'+str(rlog)+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if Zpoolimport (import) ##############
 elif r["req"]=='Zpoolimport':  
  pool=r["reply"][4].split('/')[2]
  logmsg.sendlog('Zpst02','info','system',pool)
  with open('/root/recv','a') as f:
   f.write('received Zpool from parnter :'+str(rlog)+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if clear cache ##############
 elif r["req"]=='ClearCache':  
  with open('/root/recv','a') as f:
   f.write('received ClearCache from parnter :'+str(rlog)+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if synchosts ##############
 elif r["req"]=='SyncHosts':  
  with open('/root/recv','a') as f:
   f.write('received synchosts from parnter :'+str(rlog)+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if broadcast ##############
 elif r["req"]=='broadcast':  
  with open('/root/recv','a') as f:
   f.write('received broadcast from parnter :'+str(rlog)+'\n')
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
   f.write('received LocalManualConfig from parnter :'+str(rlog)+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if HostgetIPs ##############
 elif r["req"]=='HostgetIPs':  
  with open('/root/recv2','a') as f:
   f.write('received HostgetIPs from parnter :'+str(rlog)+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if ReleasePoolLock ##############
 elif r["req"]=='ReleasePoolLock':  
  with open('/root/recv2','a') as f:
   f.write('received ReleasePoolLock from parnter :'+str(rlog)+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if GroupChange ##############
 elif r["req"]=='RemoveTargets':  
  with open('/root/recvtmp2','w') as f:
   f.write('received RemoveTarget from parnter :'+str(rlog)+'\n')
  torun=['/pace/removetargetdisks.sh',r["reply"][0]]
  with open('/root/recvtmp2','a') as f:
   f.write('received RemoveTarget from parnter :'+str(torun)+'\n')
  result=subprocess.run(torun,stdout=subprocess.PIPE)
########## if GroupChange ##############
 elif r["req"]=='GroupChange':  
  with open('/root/recv2','a') as f:
   f.write('received GroupChange from parnter :'+str(rlog)+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if UserChange ##############
 elif r["req"]=='UserChange':  
  with open('/root/recv2','a') as f:
   f.write('received UserChange from parnter :'+str(rlog)+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if UserAdd ##############
 elif r["req"]=='UserAdd':  
  with open('/root/recv2','a') as f:
   f.write('received UserAdd from parnter :'+str(rlog)+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if UserDel ##############
 elif r["req"]=='UserDel':  
  with open('/root/recv2','a') as f:
   f.write('received UserDel from parnter :'+str(rlog)+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if GroupAdd ##############
 elif r["req"]=='GroupAdd':  
  with open('/root/recv2','a') as f:
   f.write('received GroupAdd from parnter :'+str(rlog)+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if GroupDel ##############
 elif r["req"]=='GroupDel':  
  with open('/root/recv2','a') as f:
   f.write('received GroupDel from parnter :'+str(rlog)+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
########## if NTP  ##############
 elif r["req"]=='HostManualConfigNTP':  
  with open('/root/recv2','a') as f:
   f.write('received HostManualConfigNTP from parnter :'+str(rlog)+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
 ########## if TZ  ##############
 elif r["req"]=='HostManualConfigTZ':  
  with open('/root/recv2','a') as f:
   f.write('received HostManualConfigTZ from parnter :'+str(rlog)+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
  ########## if GW  ##############
 elif r["req"]=='HostManualConfigGW':  
  with open('/root/recv2','a') as f:
   f.write('received HostManualConfigGW from parnter :'+str(rlog)+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
 ########## if UpdateHosts  ##############
 elif r["req"]=='UpdateHosts':  
  with open('/root/recv2','a') as f:
   f.write('received UpdateHosts from parnter :'+str(rlog)+'\n')
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
  ########## if Exchange  ##############
 elif r["req"]=='Exchange':  
  result=subprocess.run(r["reply"],stdout=subprocess.PIPE)
 


if __name__=='__main__':
 import sys
 cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py leader'
 leader=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
 cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py leaderip'
 leaderip=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
 cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py clusternode'
 myhost=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
 cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py clusternodeip'
 myip=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
 if leader == myhost:
    etcdip = leaderip
 else:
    etcdip = myip
 msg=str({'host': 'localhost', 'req':  "{'req': 'Pumpthis', 'reply':['/TopStor/systemcheckout.sh', 'QSD3.721', 'admin', 'hi1']}"})
 do(leader, leaderip, myhost, myip, etcdip, 'b"'+msg+'"') 
