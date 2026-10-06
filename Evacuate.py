#!/usr/bin/python3
import sys
from time import time
from logqueue import queuethis, initqueue
from etcdput import etcdput as put 
from etcddel import etcddel as dels 
from Evacuatebyleader import setall
from etcdget import etcdget as get 
from sendhost import sendhost
import logmsg


discip = '10.11.11.253'

def do(leaderip,myhost, *args):
 #with open('/TopStor/tempEvacuate','w') as f:
  #f.write(" ".join([leaderip, myhost]+list(args)))
 if 'dhcpEvacuate' in args[-2]:
    dels(leaderip,'ActivePartners/'+args[-2])
    return 
 logmsg.initlog(leaderip, myhost)
 initqueue(leaderip, myhost)
 try:
  with open('/pacedata/perfmon','r') as f:
   perfmon = f.readline()
 except FileNotFoundError:
  perfmon = '0'
 if '1' in perfmon:
  queuethis('Evacuate','toremove',args[-1])
 readies=get(leaderip, 'ready','--prefix')
 if len(readies) < 2 and args[-2] in str(readies):
  return
 logmsg.sendlog('Evacuaest01','info',args[-1],args[-2])
 leader = get(leaderip, 'leader')[0]
 evacip = get(leaderip, 'ActivePartners/'+args[-2])[0]
 nextleader = str(get(leaderip,'nextlead/er')[0]).split('/')[0]    # '<host>/<ip>': the host
 if leader == myhost and leader==args[-2]:
   nextleaderip = [ host[1] for host in readies if nextleader in host[0] ][0]
   put(nextleaderip, 'bybyleader', myhost+'/'+args[-1])
   #cmdline=['/TopStor/docker_setup.sh','reset']
   #result=subprocess.run(cmdline,stdout=subprocess.PIPE)
   put(leaderip,'configured/'+args[-2],'reset')
   put(leaderip,'rebootme/'+args[-2],'pls')
    
 elif leader == myhost:
    stamp = time()
    if  nextleader == args[-2]:
     for ready in readies:
        if nextleader not in str(ready) and leader not in str(ready):
            nextleader = ready[0].split('/')[1]
            put(leaderip, 'nextlead/er',nextleader+'/'+ready[1])
            put(leaderip, 'sync/nextlead/Add_er_'+nextleader+'::'+ready[1]+'/request','nextlead_'+str(stamp))
            put(leaderip, 'sync/nextlead/Add_er_'+nextleader+'::'+ready[1]+'/request/'+myhost,'nextlead_'+str(stamp))
            break

    put(leaderip,'configured/'+args[-2],'reset')
    put(evacip,'configured/'+args[-2],'reset')
    put(evacip,'rebootme/'+args[-2],'pls')
    put(leaderip, 'sync/evacuatehost/syncfn_setall_'+args[-2]+'_'+args[-1]+'/request', 'evacuatehost_'+str(stamp))
        
    
 #logmsg.sendlog('Evacuaesu01','info',args[-1],args[-2])

if __name__=='__main__':
 do(*sys.argv[1:])
