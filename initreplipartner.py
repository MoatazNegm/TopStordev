#!/usr/bin/python3
import sys, os, subprocess, logmsg
from allphysicalinfo import getall 
from etcdgetpy import etcdget as get
from etcdgetnoport import etcdget as getnoport
from etcdputnoport import etcdput as putnoport 
from etcdput import etcdput as put 
from etcddel import etcddel as dels 
from pumpkeys import pumpkeys, initpumpkeys
from time import sleep
from time import time as stamp
from sendhost import sendhost
from secretmask import MASK
from ast import literal_eval as mtuple


def submitkeys(partner, partnerip, isleader, myhost, myhostip, leaderip, repliport, phrase):
    cmdline = '/TopStor/preparekeys.sh '+partner+' '+partnerip
    result = subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').split('\n')[0].replace(' ','_spc_')
    if 'yes' in isleader:
        z=['/TopStor/receivekeys.sh',myhost,myhostip,leaderip, repliport, phrase, result]
    else:
        z=['/TopStor/sendreceivekeys.py',partnerip, myhost,myhostip,leaderip, repliport, phrase, result]
    msg={'req': 'Exchange', 'reply':z}
    # QSD5.344: /root/sendhostparam gets the request with the pass phrase masked
    zlog = list(z)
    zlog[5 if 'yes' in isleader else 6] = MASK
    try:
        sendhost(partnerip, str(msg),'recvreply',myhost, logreq=str({'req': 'Exchange', 'reply':zlog}))
    except:
        print('the cluster is down')
        exit()
    sleep(3)
    nodeloc = 'ssh -oBatchmode=yes -i /TopStordata/'+partner+'/'+partnerip+' -p '+repliport+' -oStrictHostKeyChecking=no '+partnerip
    print('ssh -oBatchmode=yes -i /TopStordata/'+partner+'/'+partnerip+' -p '+repliport+' -oStrictHostKeyChecking=no '+partnerip)
    count = 0 
    result=subprocess.run(nodeloc.split()+['ls'],stdout=subprocess.PIPE)
    while count < 10:
        if result.returncode == 0:
            isitopen = 'open'
            print('it is open now')
            break
        count += 1
        print('still closed')
        sleep(1) 
        result=subprocess.run(nodeloc.split()+['ls'],stdout=subprocess.PIPE)
    return nodeloc,result.returncode

def pumpcluster(*bargs):
 leaderip = bargs[0]
 myhostip = bargs[1]
 myhost = bargs[2]
 partner = bargs[3]
 partnerip = bargs[4]
 repliport = bargs[5]
 phrase = bargs[6]
 leadernodeloc, returncode = submitkeys(partner, partnerip, 'yes', myhost, myhostip, leaderip, repliport, phrase)
 if returncode != 0:
    return
 initPartnerReadies(leadernodeloc, partner, partnerip, myhost, myhostip, leaderip, repliport, phrase)

def initPartnerReadies(leadernodeloc,  partner, partnerip, myhost, myhostip, leaderip, repliport, phrase,tunnelport=''): 
 if 'readyonly' in leadernodeloc:
    partnerreadies = getnoport(leaderip, str(tunnelport),'ready','--prefix')
    print(leadernodeloc, partner, partnerip, myhost)
    knownreadies = os.listdir('/TopStordata/'+partner)
    partnerleader = getnoport(leaderip, str(tunnelport),'leader')[0]
    print('partnerleader',partnerleader)
 else:
    cmd = leadernodeloc + ' /TopStor/etcdget.py '+partnerip+' leader'
    partnerleader =subprocess.run(cmd.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','')
    cmd = leadernodeloc + ' /TopStor/etcdget.py '+partnerip+' ready --prefix'
    partnerreadies =subprocess.run(cmd.split(),stdout=subprocess.PIPE).stdout.decode('utf-8')[:-1].split("\n")
 cmd=' /TopStor/etcdget.py '+leaderip+' replinextport' 
 port2 =subprocess.run(cmd.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','')
 for tup in partnerreadies:
    if 'readyonly' in leadernodeloc:
        ready = tup
        if ready[1] in str(knownreadies):
            continue 
    else:
        ready = mtuple(tup)
    if partnerleader in ready[0]:
        isleader = 'yes'
        cmd = ' /TopStor/rmkeys.sh '+partner+' '+partnerip
        subprocess.run(cmd.split(),stdout=subprocess.PIPE).stdout.decode('utf-8')
    else:
        isleader = 'no'
    nodeloc, _ = submitkeys(partner, ready[1], isleader,  myhost, myhostip, leaderip, repliport, phrase)
    if partnerleader in ready[0]:
        leadernodeloc = nodeloc
        portcmd=' /TopStor/etcdget.py '+partnerip+' replinextport' 
    else:
        portcmd=' /TopStor/etcdget.py '+ready[1]+' replinextport' 
    cmd = leadernodeloc + portcmd
    port1 =subprocess.run(cmd.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','')
    if int(port1) > int(port2):
        selectedport = int(port1) 
    else:
        selectedport = int(port2) 
    print('selectedport',port1, port2, selectedport)
    cmdline = '/TopStor/remotetunneladd.sh '+partner+' '+partnerip+' '+leaderip+' '+ready[1]+' '+repliport+' '+str(selectedport)
    print('/TopStor/remotetunneladd.sh '+partner+' '+partnerip+' '+leaderip+' '+ready[1]+' '+repliport+' '+str(selectedport))
    subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8')
    leader=get(leaderip,'leader')[0]
    if leader in myhost:
        etcdip = leaderip
    else:
        etcdip = myhostip
    if partnerleader in ready[0]:
        partneretcdip = partnerip
    else:
        partneretcdip = ready[1]
    cmdline = nodeloc + ' /TopStor/etcdput.py '+partneretcdip+' replinextport '+str(selectedport+1)
    subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8')
    cmdline = nodeloc + ' /TopStor/etcdget.py '+partnerip+' Partner '+leaderip
    myalias = subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').split('Partner/')[1].split("'")[0]
    cmdline = nodeloc + ' /TopStor/etcdput.py '+partneretcdip+' replireverse/'+myalias+'/'+partner+'/'+leaderip+' '+ str(selectedport)
    subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8')
    cmdline = '/TopStor/etcdput.py '+etcdip+' replinextport '+str(selectedport+1)
    subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8')
    port2 = str(selectedport+1)
    return
    
 
 

if __name__=='__main__':
 if 'readyonly' in sys.argv[1]:
    initPartnerReadies(*sys.argv[1:]) 
 else:
    pumpcluster(*sys.argv[2:])
