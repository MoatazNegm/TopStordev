#!/usr/bin/python3
import sys, subprocess, datetime
from logqueue import queuethis, initqueue
from etcdgetpy import etcdget as get
from sendhost import sendhost

def create(leader, leaderip, myhost, myhostip, etcdip, pool, name, ipaddr, ipsubnet, vtype,*args):
    volsip = get(etcdip,'volume',ipaddr)
    volsip = [ x for x in volsip if 'active' in str(x) ]
    nodesip = get(etcdip, 'Active',ipaddr) 
    notsametype = [ x for x in volsip if vtype not in str(x) ]
    if (len(nodesip) > 0 and 'Active' in str(nodesip))or len(notsametype) > 0:
        print(ipaddr)
        print(len(nodesip), nodesip)
        #/TopStor/logmsg.py ISCSIwa01 warning $userreq $ipaddr 
        print(len(notsametype), notsametype)
        print(' the ip address is in use ')
        return
    resname = vtype+'-'+ipaddr
    #cmdline='rm -rf /TopStordata/tempsmb.'+ipaddr
    #subprocess.run(cmdline.split(),stdout=subprocess.PIPE)  
    mounts = pool+'/'+name
    for vol in volsip:
        if vol in notsametype:
           continue
        #leftvol = vol[0].split('/')[4]
        #mounts += '-v/'+pool+'/'+leftvol+':/'+pool+'/'+leftvol+':rw'
        #with open('/TopStordata/tempsmb.'+ipaddr,'a') as fip:
        #    with open('/TopStordata/smb.'+leftvol, 'r') as fvol:
        #        fip.write(fvol.read())
    #cmdline = 'cp /TopStordata/tempsmb.'+ipaddr+' /TopStordata/smb.'+ipaddr
    #subprocess.run(cmdline.split(),stdout=subprocess.PIPE)  
    print('hihihihi')
    #print('/TopStor/cifs.sh '+resname+' '+mounts+' '+ipaddr+' '+ipsubnet+' '+vtype+' '+" ".join(args))
    cmdline='/TopStor/iscsi.sh $leaderip $pool $name $ipaddr $ipsubnet $portalport $targetiqn $chapuser $chappas'
    cmdline='/TopStor/iscsi.sh $leaderip $pool $name $ipaddr $ipsubnet $portalport $targetiqn $chapuser $chappas'
    cmdline = '/TopStor/iscsi.sh '+resname+' '+mounts+' '+ipaddr+' '+ipsubnet+' '+vtype+' '+" ".join(args)
    subprocess.run(cmdline.split(),stdout=subprocess.PIPE)  
    print(mounts)
    return
    #if len(checkipaddr1) != 0 or len :

 

if __name__=='__main__':
 leader = sys.argv[1]
 leaderip = sys.argv[2]
 myhost = sys.argv[3]
 myhostip = sys.argv[4]
 etcdip = sys.argv[5]
 pool = sys.argv[6]
 name = sys.argv[7]
 ipaddr = sys.argv[8]
 ipsubnet = sys.argv[9]
 vtype = sys.argv[10]
 initqueue(leaderip, myhost)
 with open('/root/cifspytmp','w') as f:
  # the trace without the CHAP secret (the last argument; QSD5.341 test 653)
  f.write(str(sys.argv[:-1]+['***'] if len(sys.argv) > 14 else sys.argv))
 create(leader, leaderip, myhost, myhostip, etcdip, pool, name, ipaddr, ipsubnet, vtype,*sys.argv[11:])
