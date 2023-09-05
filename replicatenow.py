#!/usr/bin/python3
import sys, subprocess, logmsg
from allphysicalinfo import getall 
from etcdgetpy import etcdget as get
from etcdgetnoport import etcdget as getnoport
from etcdputnoport import etcdput as putnoport 
from etcdput import etcdput as put 
from etcddel import etcddel as dels 
from pumpkeys import pumpkeys, initpumpkeys
from time import sleep
from time import time as stamp


allinfo = {}
phrase = ''
myclusterip = ''
pport = ''
nodeloc = ''
replitype = 'Receiver'
isitopen = 'closed'

def dosync(sync,  *args):
  global leaderip, leader
  dels(leaderip, 'pullsync',sync) 
  put(leaderip, *args)
  put(leaderip, args[0]+'/'+leader,args[1])
  return 


def checkpartner(nodeloccmd):
 global allinfo, phrase, myclusterip, pport, nodeloc, replitype, leaderip, etcdip, isitopen
 isitopen == 'closed'
 count = 0
 resultdecod = 0
 print('sending to the cluster', nodeloccmd)
 try:
    result=subprocess.run(nodeloccmd.split(),stdout=subprocess.PIPE)
    if result.returncode == 0: 
        isitopen = 'open'
        resultdecod = result.stdout.decode()
 except:
    resultdecod = 0
 return isitopen , resultdecod


def usetunnelport(receiver,cmd):
 global allinfo, phrase, myclusterip, pport, nodeloc, replitype, leaderip, etcdip
 nodesinfo = get(etcdip, 'repliPartner/'+receiver,'--prefix')
 #cmddic = { 'getnoport',getnoport, 'putnoport':putnoport }
 for node in nodesinfo:
    tunnelport = node[1].split('/')[-1]
    newcmd = cmd.replace('TUNNELPORT',tunnelport)
    cmdlst = newcmd.split()
    print(cmdlst)
    globals()[cmdlst[0]](*cmdlst[1:]) 

def createnodeloc(receiver, cmd, userreq):
 global allinfo, phrase, myclusterip, pport, nodeloc, replitype, leaderip, etcdip
 partnerinfo = get(etcdip, 'Partner/'+receiver)[0].split('/')
 remoteCluster = partnerinfo[0]
 replitype = partnerinfo[1]
 pport = partnerinfo[2]
 phrase = partnerinfo[-1]
 print(partnerinfo)
 print(replitype, pport, phrase, leaderip )
 nodesinfo = get(etcdip, 'repliPartner/'+receiver,'--prefix')
 isopen = 'closed'
 print('hi',nodesinfo)
 #nodesinfo.append(('hi/hi/'+partnerinfo[0],'hi')) 
 isopen = 'close'
 print(nodesinfo)
 for node in nodesinfo:
  print(node)
  nodeip = node[0].split('/')[2]
  nodeloc = 'ssh -oBatchmode=yes -i /TopStordata/'+nodeip+'_keys/'+nodeip+' -p '+pport+' -oStrictHostKeyChecking=no ' + nodeip 
  nodeloccmd = nodeloc+' '+ cmd
  print('################################################333')
  print(nodeip)
  print(nodeloc)
  isopen, response = checkpartner(nodeloccmd)
  print(isopen)
  print(response)
  print('################################################333')
  if isopen == 'open':
    return nodeip, nodeloc, response
 nodeip = remoteCluster
 pumpkeys(nodeip, replitype, pport, phrase)
 nodeloc = 'ssh -oBatchmode=yes -i /TopStordata/'+nodeip+'_keys/'+nodeip+' -p '+pport+' -oStrictHostKeyChecking=no ' + nodeip 
 nodeloccmd = nodeloc+' '+ cmd
 isopen, response = checkpartner(nodeloccmd)
 finalresponse = response
 if isopen != 'open':
    print('port is not open')
    finalresponse = 'result_failresult_ connection to all the nodes  cluster '+nodeip
 else:
    nodeloccmd = nodeloc +' '+ '/TopStor/nodeinfo.sh '+remoteCluster 
    print('################################################333')
    print(nodeip)
    print(nodeloccmd)
    print('################################################333')
    print('sending checkpartner')
    isopen, response = checkpartner(nodeloccmd)
    print('response',response)
    if isopen != 'open':
        finalresponse = 'result_failresult_ connection to remote node '+nodeip
    else:
        print('################################################333')
        print(response)
        print('################################################333')
        partnerinfo = response.split('_')
        try: 
            remotenextport = int(partnerinfo[4])
        except:
            remotenextport = 2380
        try:
            mynextport = int(get(etcdip,'replinextport')[0])
        except:
            mynextport = 2380
        replileader = partnerinfo[5]
        tunnelport = [ remotenextport ,mynextport ]
        print(tunnelport)
        tunnelport.sort()
        tunnelport = tunnelport[-1]+1 
        print(tunnelport)
        pumpkeys(partnerinfo[3], replitype, pport, phrase)
        put(etcdip,'repliPartner/'+receiver+'/'+partnerinfo[3], partnerinfo[2]+'/'+str(tunnelport))
        #if etcdip == leaderip:
        put(etcdip, 'replinextport',str(tunnelport))
        print('/TopStor/remotetunneladd.sh '+receiver+' '+remoteCluster+' '+leaderip+' '+partnerinfo[3]+' '+pport+' '+str(tunnelport))
        cmdline = '/TopStor/remotetunneladd.sh '+receiver+' '+remoteCluster+' '+leaderip+' '+partnerinfo[3]+' '+pport+' '+str(tunnelport)
        subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8')
        cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py clusternode'
        myhost=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
        cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py clusternodeip'
        myip=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
        remotepartner = getnoport(leaderip, str(tunnelport),'Partner',leaderip)
        if leaderip not in remotepartner:
            dels(leaderip,'Partner',receiver)
            logmsg.sendlog('Partnerfa01','info',userreq, receiver.split('_')[0])
        dels(leaderip,'sync','request/'+receiver)
        myalias = remotepartner[0][0].split('/')[1]
        putnoport(leaderip, str(tunnelport),'replireverse/'+myalias+'/'+receiver+'/'+leaderip, str(tunnelport))
        checkifok = getnoport(leaderip, str(tunnelport),'replireverse/'+myalias+'/'+receiver+'/'+leaderip)[0]
        if str(tunnelport) in checkifok:
            putnoport(leaderip, str(tunnelport),'replinextport', str(tunnelport))
            logmsg.sendlog('Partnersu01','info',userreq, receiver.split('_')[0])
        else:
            dels(leaderip,'Partner',receiver)
            logmsg.sendlog('Partnerfa01','error',userreq, receiver.split('_')[0])

 if nodeip == remoteCluster and isopen != 'open' :
   finalresponse = 'result_failresult_ connection to all the nodes in the remote cluster '+nodeip
    
 return nodeip, nodeloc, finalresponse
 

def replistream(receiver, nodeip, snapshot, nodeowner, poolvol, pool, volume, csnaps):
 global allinfo, phrase, myclusterip, pport, nodeloc, replitype, leaderip, etcdip
 myvol = pool+'/'+volume 
 mysnaps = sorted(allinfo['volumes'][volume]['snapshots'], key= lambda x : x.split('.')[-1], reverse=True)
 oldsnap = 'noold'
 for snap in mysnaps:
  if snap in csnaps:
   oldsnap = snap
   break
 volumeline = get(etcdip, 'volume', volume)[0]
 volumeinfo = volumeline[1].split('/') 
 volgrps = volumeinfo[4]
 voltype = volumeline[0].split('/')[1]
 if voltype in 'NFS':
    cmd = '/usr/sbin/zfs get quota '+myvol+' -H'
    volip = volumeinfo[9]
    volsubnet = volumeinfo[10]
    volgrps = volumeinfo[8]
    extras = ''
 elif voltype in 'ISCSI':
    cmd = '/usr/sbin/zfs get volsize '+myvol+' -H'
    volip = volumeinfo[2]
    volsubnet = volumeinfo[3]
    extras = volumeinfo[5]
 else:
    cmd = '/usr/sbin/zfs get quota '+myvol+' -H'
    volip = volumeinfo[7]
    volsubnet = volumeinfo[8]
    extras = ''
 quota=subprocess.run(cmd.split(' '),stdout=subprocess.PIPE).stdout.decode().split('\t')[2]
 oldsnap = 'noold'
 nodeloccmd = nodeloc + ' /TopStor/getlatestsnap.sh '+volume
 try:
  isopen, result = checkpartner(nodeloccmd)
 except:
   print('result_failresult_ connection to the remote parnter')
   exit()

 remotesnap = result.split('result_')
 if remotesnap != 'noold':
  cmd = 'zfs list -t snapshot'
  mysnaps = subprocess.run(cmd.split(' '),stdout=subprocess.PIPE).stdout.decode()
  if remotesnap[1] in mysnaps:
   oldsnap = remotesnap[2] 
 nodeloccmd = nodeloc + ' /TopStor/targetcreatevol.sh '+poolvol+' '+volip+' '+volsubnet+' '+quota+' '+voltype+' '+' '+oldsnap+' '+volgrps+' '+extras
 isopen, result = checkpartner(nodeloccmd)
 if 'open' not in isopen:
   print('result_failresult_ connection to the remote parnter')
   exit()

 response = result.split('result_')
 print('the response of create:',response)
 if oldsnap == 'noold':
  response[1] = 'newvol/@new'
 if 'problem/@problem' in response[1]:
  print(' a problem creating/using the volume in the remote cluster')
  return
 elif 'newvol/@new' in response[1]:
  remvol = result.split('volume_')[1]
  print('/TopStor/sendzfs.sh new '+ myvol+'@'+snapshot +' '+ remvol +' '+ nodeloc.replace(' ','%%'))
  cmd = '/TopStor/sendzfs.sh new '+ myvol+'@'+snapshot +' '+ remvol +' '+ nodeloc.replace(' ','%%')
 else:
  #cmd = './sendzfs.sh old '+myvol+'@'+lastsnap+' '+myvol+'@'+snapshot+' '+poolvol+' '+nodeloc
  remvol = result.split('volume_')[1]
  myoldsnap = oldsnap.split('@')[1]
  cmd = '/TopStor/sendzfs.sh old '+myvol+'@'+myoldsnap+' '+myvol+'@'+snapshot+' '+remvol +' '+nodeloc.replace(' ','%%')
  print('/TopStor/sendzfs.sh old '+myvol+'@'+myoldsnap+' '+myvol+'@'+snapshot+' '+remvol +' '+nodeloc.replace(' ','%%'))
 put(leaderip,'running/'+receiver, 'running')
 stream = subprocess.run(cmd.split(' '),stdout=subprocess.PIPE).stdout.decode()
 dels(leaderip,'running/'+receiver)
 print('streaming: ',stream)
 print('start checking csnaps')
 csnaps = csnaps.split(',')
 cmd = '/usr/sbin/zfs list -t snapshot -o name'
 mysnaps=subprocess.run(cmd.split(' '),stdout=subprocess.PIPE).stdout.decode()
 destroy = ''
 for snap in csnaps:
  if snap == 'csnaps':
   continue
  if snap not in mysnaps:
   destroy = destroy + poolvol+'@'+snap+',' 
 if len(destroy) > 5:
  nodeloccmd = nodeloc + ' /TopStor/zfsdestroy.sh '+destroy[:-1]
  with open('/root/destroynow','w') as f:
    f.write(cmd+'\n')
  isopen , _ = checkpartner(nodeloccmd)
  if 'open' not in isopen:
   print('result_failresult_ connection to the remote parnter')
   exit()

 
 nodeloccmd = '/usr/sbin/zfs list -H -t snapshot -o name'
 isopen , snaps = checkpartner(nodeloccmd)
 if 'open' not in isopen:
  print('result_failresult_ connection to the remote parnter')
  exit()
 print('-----------------------------------')
 print('end checking csnaps', snaps)
 print('-----------------------------------')
 if snapshot in str(snaps):
    print('replicatenow_successreplicatenow_')
    return 'success' 
 else:
    print('replicatenow_failreplciatenow_')
    return 'fail'
 return stream

def repliparam(snapshot, receiver, userreq='system'):
 global allinfo, phrase, myclusterip, pport, nodeloc, replitype, leaderip, etcdip
 if snapshot == 'sync':
  syncpush(receiver, userreq)
  return
 alldsks = get(leaderip, 'host','current')
 allinfo = getall(leaderip, alldsks)
 volume = snapshot.split('/')[1].split('@')[0]
 pool = snapshot.split('/')[0]
 snapshot = snapshot.split('@')[1].replace(' ','')
 volused = str(allinfo['volumes'][volume]['referenced'])
 snapused = '0' 
 cmd = ' /TopStor/repliSelection.py '+volume+' '+volused+' '+snapshot
 nodeip, nodeloc, finalresponse = createnodeloc(receiver, cmd, userreq)
 if 'fail' in finalresponse:
  print('(fail) no node is open for replication in the '+receiver)
  return 'closed'
 if 'No_vol_space' in str(finalresponse):
  print('(fail) No space in the receiver: '+receiver)
  return 'No_Sppue'
 finalresponse = finalresponse.split('result_')[1]
 print('selection',finalresponse)
 nodeowner = finalresponse.split(':')[0]
 poolvol = finalresponse.split(':')[1].split('@')[0]
 try:
  csnaps = finalresonse.split('@')[1]
 except:
  csnaps = 'noold'
 result = replistream(receiver, nodeip, snapshot, nodeowner, poolvol, pool, volume, csnaps)
 if 'fail' in result:
  print('fail')
  cmd = '/usr/sbin/zfs destroy -r '+' '+pool+'/'+volume+'@'+snapshot 
 else:
  print('success ',result)
  nodeloccmd = nodeloc+'  /TopStor/setsnapsender.py '+snapshot+' '+leaderip
  isopen , _ = checkpartner(nodeloccmd)
  if 'open' not in isopen:
   print('result_failresult_ connection to the remote parnter')
   exit()
  #subprocess.run(cmd.split(' '),stdout=subprocess.PIPE).stdout.decode()
  cmd = '/usr/sbin/zfs set partner:receiver='+receiver.split('_')[0]+' '+pool+'/'+volume+'@'+snapshot
 subprocess.run(cmd.split(' '),stdout=subprocess.PIPE).stdout.decode()
 #return _'+volume, volused, snapshot+'result_'
 return result

def getusershash():
 global allinfo, phrase, myclusterip, pport, nodeloc, replitype, leaderip, etcdip
 usershash = get(leaderip, 'usershash','--prefix')
 #usershash = [ x for x in usershash if 'admin' not in x[0] ]
 return usershash

def getusersinfo():
 global allinfo, phrase, myclusterip, pport, nodeloc, replitype, leaderip, etcdip
 usersinfo = get(leaderip, 'usersinfo','--prefix')
 #usersinfo = [ x for x in usersinfo if 'admin' not in x[0] ]
 return usersinfo

def getgroups():
 global allinfo, phrase, myclusterip, pport, nodeloc, replitype, leaderip, etcdip
 groups = get(leaderip, 'usersigroup','--prefix')
 #groups = [ x for x in groups if 'admin' not in x[0] ]
 return groups 

def packagekeys(key,exception):
 global allinfo, phrase, myclusterip, pport, nodeloc, replitype, leaderip, etcdip, leader
 keylist = get(leaderip, key, '--prefix')
 keylist = [ x for x in keylist if  exception not in x[0] ]
 print(keylist)
 stringlist = []
 for key in keylist:
  stringlist.append('tuple%'.join(key))
 print('stringlist', stringlist)
 keystring = 'list%'.join(stringlist).replace('pushsync/','')
 print(keystring)
 return keystring 

def syncpush(receiver, userreq):
 global allinfo, phrase, myclusterip, pport, nodeloc, replitype, leaderip, etcdip, leader
 logmsg.sendlog('Partnerst01','info',userreq, receiver.split('_')[0])
 #usershash = getusershash()
 #usersinfo = getusersinfo()
 #groups = getgroups()
 #usershash = packagekeys('usershash','xxadmin')
 #usersinfo = packagekeys('usersinfo','xxadmin')
 #groups = packagekeys('usersigroup','xxadmin')
 stampit = str(stamp())
 #put(leaderip, 'pushsync/sync/user/initial/request','user_'+stampit)
 #dosync('user_', 'pushsync/sync/user/initial/request','user_'+stampit)
 #put(leaderip, 'pushsync/sync/group/initial/request','group_'+stampit)
 #dosync('group_','pushsync/sync/group/initial/request','group_'+stampit)
 #syncinfo = packagekeys('pushsync/sync', '/dhcp')
 #cmd = '/TopStor/replisyncpull.py '+usershash+' '+usersinfo+' '+groups+' '+syncinfo
 cmd = 'pwd'
 nodeip, nodeloc, finalresponse = createnodeloc(receiver, cmd,userreq)
 cmd = 'putnoport '+leaderip+' TUNNELPORT tempkey  32322'+leader
 usetunnelport(receiver,cmd)
 print('finalresponse', finalresponse)
 if 'fail' in finalresponse:
    logmsg.sendlog('Partnerfa01','error',userreq, receiver.split('_')[0])
 return finalresponse

def repliinit(ldrip, ldr, etip):
 global leaderip, etcdip, leader
 leaderip = ldrip
 etcdip = etip
 leader = ldr
 initpumpkeys('init')

if __name__=='__main__':
 leaderip =  sys.argv[1]
 etcdip =  sys.argv[2]
 initpumpkeys('init')
 cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py clusternode'
 myhost=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
 cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py leader'
 leader=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
 
 logmsg.initlog(leaderip, myhost)
 with open('/root/replicatenowpy','w') as f:
    f.write(' '.join(sys.argv[1:]))
 repliparam(*sys.argv[3:])
