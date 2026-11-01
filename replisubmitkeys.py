#!/usr/bin/python3
import subprocess
import sys
from time import sleep
from sendhost import sendhost
from secretmask import MASK

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

if __name__ == "__main__":
    if len(sys.argv) != 9:
        print(f"Usage: {sys.argv[0]} <partner> <newpartnernodeip> <isleader (yes/no)> <myhost> <myhostip> <leaderip> <repliport> <phrase>")
        sys.exit(1)

    partner, partnerip, isleader, myhost, myhostip, leaderip, repliport, phrase = sys.argv[1:9]
    
    nodeloc, exit_code = submitkeys(partner, partnerip, isleader, myhost, myhostip, leaderip, repliport, phrase)
    sys.exit(exit_code)
