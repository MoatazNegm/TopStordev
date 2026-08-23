#!/bin/python
import sys, subprocess, re, zlib, json, base64
from etcdgetpy import etcdget as get 
from etcdput import etcdput as put
from etcddel import etcddel as dels 
from time import time , sleep
from collectconfig import collectConfig
from sendhost import sendhost

readies = 0 

def postchange(hostname, hostip):
 global leaderip, myhost
 cmndstring = '/TopStor/collectconfig.py '+leaderip+' '+hostname
 print('cmd is', cmndstring)
 z= cmndstring.split(' ')
 msg={'req': 'Pumpthis', 'reply':z}
 sendhost(hostip, str(msg),'recvreply',myhost)


def json_zip(j):
    j = base64.b64encode(
            zlib.compress(
                json.dumps(j).encode('utf-8')
            )
        ).decode('ascii')
    
    return j

def json_unzip(j, insist=True):
    try:
        j = zlib.decompress(base64.b64decode(j))
    except:
        raise RuntimeError("Could not decode/unzip the contents of "+j)

    try:
        j = json.loads(j)
    except:
        raise RuntimeError("Could interpret the unzipped contents of "+j)

    return j

def updateConfig(leaderip, nodeName):
    cmdline = '/TopStor/collectconfig.sh'.split()
    content = subprocess.run(cmdline,stdout=subprocess.PIPE, text=True).stdout
    print(content)
    zipped = json_zip(content)
    put(leaderip, 'getconfig/'+nodeName, zipped)

def getConfig(ldrip, mynode):
    global leaderip,readies, myhost
    leaderip = ldrip
    myhost = mynode
    with open('/root/collectconfig','w') as f:
        f.write(leaderip+' '+mynode)
    stamp=str(time())
    dels(leaderip,'getconfig','--prefix')
    readies = get(leaderip,'ready/','--prefix')
    for ready in readies:
     readyname = ready[0].split('/')[1]
     readyip = ready[1]   
     postchange(readyname, readyip)
    counter = 0
    while counter < 60:
        counter += 1
        sleep(3)
        print('checking',counter)
        
        print('getetcd',get(leaderip,'getconfig','--prefix'))
        if len(get(leaderip,'getconfig','--prefix')) == len(readies):
            print('all is done')
            counter = 100
    
def downloadConfig(ldrip,mynode):
    global leaderip, readies, myhost
    leaderip = ldrip
    myhost = mynode
    cmdline = 'rm -rf /TopStordata/config*'.split()
    content = subprocess.run(cmdline,stdout=subprocess.PIPE, text=True).stdout
    readies = get(leaderip, 'ready/','--prefix')
    for ready in readies:
        noden = ready[0].split('/')[1]
        nodeip = ready[1]
        try:
            zipped = get(leaderip, 'getconfig/'+noden )[0]
            unzipped = json_unzip(zipped)
            with open("/TopStordata/" + 'config_'+ noden + ".txt", "w") as file:
                file.write(unzipped)
        except Exception as e:
            print(f"Error downloading config for {noden}: {e}")
    return unzipped if 'unzipped' in dir() else ''

if __name__=='__main__':
    leaderip = sys.argv[1]
    myhost = sys.argv[2]
    with open('/root/collectconfig','w') as f:
        f.write(leaderip+' '+myhost)
    getConfig(leaderip, myhost)
    downloadConfig(leaderip, myhost)

