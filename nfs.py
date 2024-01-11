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
        print(len(notsametype), notsametype)
        print(' the ip address is in use ')
        return
    resname = vtype+'-'+ipaddr
    cmdline='rm -rf /TopStordata/tempnfs.'+ipaddr
    subprocess.run(cmdline.split(),stdout=subprocess.PIPE)  
    cmdline='rm -rf /TopStordata/exportsip.'+ipaddr
    subprocess.run(cmdline.split(),stdout=subprocess.PIPE)  
    mounts =''
    for vol in volsip:
        if vol in notsametype:
           continue
        leftvol = vol[0].split('/')[4]
        print('leftvol',leftvol)
        print('leftvol','/'+pool+'/exports.'+leftvol)
        mounts += '-v/'+pool+'/'+leftvol+':/'+pool+'/'+leftvol+':rw'
        with open('/TopStordata/tempnfs.'+ipaddr,'a') as fip:
            try:
                with open('/'+pool+'/exports.'+leftvol, 'r') as fvol:
                    fip.write(fvol.read())
            except:
               continue 
    cmdline = 'cp /TopStordata/tempnfs.'+ipaddr+' /TopStordata/exportsip.'+ipaddr
    subprocess.run(cmdline.split(),stdout=subprocess.PIPE)  
    #if '_' not in vtype:
    #    cmdline = 'cp /TopStor/VolumeNFSupdate.sh /etc/'
    #    subprocess.run(cmdline.split(),stdout=subprocess.PIPE)  
    print('hihihihi')
    print('/TopStor/nfs.sh '+resname+' '+mounts+' '+ipaddr+' '+ipsubnet+' '+vtype+' '+" ".join(args))
    cmdline = '/TopStor/nfs.sh '+resname+' '+mounts+' '+ipaddr+' '+ipsubnet+' '+vtype+' '+" ".join(args)
    subprocess.run(cmdline.split(),stdout=subprocess.PIPE)  
    #if '_' not in vtype:
    #    users=get(etcdip,'usershash','--prefix')
    #    users=[x for x in users if 'admin' not in x[0] ]
    #    for user in users:
    #        username = user[0].split('/')[1]
    #        cmdline = '/TopStor/decthis.sh '+username+' '+user[1]
    #        passwd = subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode().split('_result')[1]
    #        cmdline = 'docker exec '+resname+' /hostetc/smbuserfix.sh x '+username+' '+passwd
    #        subprocess.run(cmdline.split(),stdout=subprocess.PIPE)  
            
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
 with open('/root/nfspytmp','w') as f:
  f.write(str(sys.argv))
 create(leader, leaderip, myhost, myhostip, etcdip, pool, name, ipaddr, ipsubnet, vtype,*sys.argv[11:])
