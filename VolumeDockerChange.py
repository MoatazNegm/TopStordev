#!/usr/bin/python3
import subprocess,sys


def delcifs(*args):
 oldipaddr = args[0]
 oldsubnet = args[1]
 vtype = args[2]
 res = vtype+'-'+oldipaddr 
 cmdline = 'docker rm -f '+res
 result = subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8')
 # QSD5.351: through rmvoladdr.sh (any prefix, the live interface in the container flavour) and only when no OTHER
 # share of this node still has the address (CIFS shares of one context share it: removing it cut them off);
 # args[3] = the dataset being changed (passed by VolumeChangeCIFS), it does not count as a user of the address
 dataset = args[3] if len(args) > 3 else ''
 cmdline = ['/TopStor/rmvoladdr.sh', oldipaddr, oldsubnet, dataset]
 result = subprocess.run(cmdline,stdout=subprocess.PIPE).stdout.decode('utf-8')
   
   
if __name__=='__main__':
 with open('/root/volumedockerchange','w') as f:
    f.write(str(sys.argv[1:])+'\n')
 delcifs(*sys.argv[1:])
