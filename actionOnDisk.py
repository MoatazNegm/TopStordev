#!/usr/bin/python3
import sys, subprocess
from logmsg import sendlog, initlog
from etcdput import etcdput as put
from etcdget import etcdget as get 
from etcddel import etcddel as dels
from time import time as stamp



def dosync(sync,  *args):
  global leaderip, leader
  dels(leaderip, 'sync',sync)
  put(leaderip, *args)
  put(leaderip, args[0]+'/'+leader,args[1])
  return

def control(*argv):
    global leaderip, leader
    myhost = argv[0]
    leaderip = argv[2]
    user = argv[1]
    action = argv[3]
    pool = argv[4]
    disk = argv[5]
    exception = get(leaderip, 'offlinethis','--prefix')
    if pool in str(exception) and 'offline' in action:
        return
    stampit = str(stamp())
    cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py leader'
    leader=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
    put(leaderip,'offlinethis/'+pool,disk)
    cmdline = ['zpool', action, pool, disk]
    print(' '.join(cmdline))
    result = subprocess.run(cmdline, capture_output=True)
    error = str(result.stderr.decode()).replace('\n\n','\n').split('\n')
    error = [i for i in error if i] 
    initlog(leaderip,myhost)
    if (not error or error[0] == ''):
        if (action == 'offline'):
            sendlog('Dist8', 'info', user, disk)
        else:
            dels(leaderip,'offlinethis/'+pool,disk)
            sendlog('Dist10', 'info', user, disk)
        dosync('offlinethis_', 'sync/offlinethis/add/request','offlinethis_'+stampit)
    else:
        if (action == 'offline'):
            dels(leaderip,'offlinethis/'+pool,disk)
            sendlog('Dist9', 'error', user, disk)
            dosync('offlinethis_', 'sync/offlinethis/add/request','offlinethis_'+stampit)
        else:
            sendlog('Dist11', 'error', user, disk)
    
if __name__=='__main__':
    with open('/root/actionOnDisk','w') as f:
        f.write(' '.join(sys.argv[1:])+'\n')
    control(*sys.argv[1:])
