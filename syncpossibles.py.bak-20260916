#!/usr/bin/python3
from etcdput import etcdput as put
from etcdget import etcdget as get 
from etcddel import etcddel as dels 
import sys

def syncpls(*args):
 leaderip=args[0]
 discip=args[1]
 donemembers = get(leaderip,'Active','--prefix')
 excepts = [] 
 poses = get(discip,'possible','--prefix')
 for pos in poses:
    host=pos[0].split('/')[1]
    if host not in str(donemembers) and host not in str(excepts):
        dels(leaderip,pos[0])
        hostip = pos[1]
        put(leaderip,pos[0],pos[1])
 return 


if __name__=='__main__':
  syncpls(*sys.argv[1:])

