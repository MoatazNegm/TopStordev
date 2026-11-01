#!/usr/bin/python3
import sys, subprocess
from sendhost import sendhost
from time import sleep 
from etcdget import etcdget as get
from secretmask import phrase_decrypt, MASK

def initpumpkeys(*args):
    global leader, leaderip, myhost, myhostip
    if args[0] == 'init':
        cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py leader'
        leader=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
        cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py leaderip'
        leaderip=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
        cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py clusternode'
        myhost=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
        cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py clusternodeip'
        myhostip=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
    else:
        leader = args[0]
        leaderip = args[1]
        myhost = args[2]
        myhostip = args[3]
def pumpthis(receiver):
    global leader, leaderip, myhost, myhostip
    partnerip = receiver[0].split('/')[2]
    replitype = 'Receiver'
    repliport = receiver[1].split('/')[1]
    cluster = receiver[0].split('/')[1]
    # QSD5.344: the stored phrase is encrypted ('enc~...'); a clear phrase of an older version is used as it is
    phrase = phrase_decrypt(cluster, get(leaderip, 'Partner',cluster)[0][1].split('/')[-1])
    pumpkeys(partnerip, replitype, repliport, phrase)
    
def pumpall():
    global leader, leaderip, myhost, myhostip
    receivers = get(leaderip, 'repliPartner','_Receiver')
    for receiver in receivers:
        pumpthis(receiver)

def pumpkeys(*bargs):
 global leader, leaderip, myhost, myhostip
 print(str(bargs[:3]))      # QSD5.344: not the pass phrase (bargs[3])
 partnerip = bargs[0]
 replitype = bargs[1]
 repliport = bargs[2]
 phrase = bargs[3]
 cmdline = '/TopStor/preparekeys.sh '+partnerip
 result = subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').split('\n')[0].replace(' ','_spc_')
 z=['/TopStor/receivekeys.sh',myhost,myhostip,leaderip, replitype, repliport, phrase, result]
 msg={'req': 'Exchange', 'reply':z}
 # QSD5.344: the printed request and /root/sendhostparam carry the pass phrase masked
 zlog = z[:6]+[MASK]+z[7:]
 print({'req': 'Exchange', 'reply':zlog})
 sendhost(partnerip, str(msg),'recvreply',myhost, logreq=str({'req': 'Exchange', 'reply':zlog}))
 sleep(2)
 nodeloc = 'ssh -oBatchmode=yes -i /TopStordata/'+partnerip+'_keys/'+partnerip+' -p '+repliport+' -oStrictHostKeyChecking=no '+partnerip+' ls'
 print(nodeloc)
 count = 0 
 while count < 10:
        result=subprocess.run(nodeloc.split(),stdout=subprocess.PIPE)
        if result.returncode == 0:
            isitopen = 'open'
            print('it is open now')
            break
        count += 1
        print('still closed')
        sleep(1) 
  

if __name__=='__main__':
 initpumpkeys('init')
 if sys.argv[1] == 'pumpall':
    pumpall()
 elif sys.argv[1] == 'pumpthis':
    receiver = get(leaderip, 'repliPartner', sys.argv[2])
    if len(str(receiver)) > 0 :
        pumpthis(receiver[0])
 else:
    pumpkeys(*sys.argv[1:])
