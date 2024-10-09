#!/usr/bin/python3
import subprocess,sys


def delcifs(*args):
 oldipaddr = args[0]
 oldsubnet = args[1]
 vtype = args[2]
 res = vtype+'-'+oldipaddr 
 cmdline = 'docker rm -f '+res
 result = subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8')
 cmdline='nmcli conn mod cmynode -ipv4.addresses '+oldipaddr+'/'+oldsubnet
 result = subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8')
 cmdline='nmcli conn up cmynode'
 result = subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8')
   
   
if __name__=='__main__':
 with open('/root/volumedockerchange','w') as f:
    f.write(str(sys.argv[1:])+'\n')
 delcifs(*sys.argv[1:])
