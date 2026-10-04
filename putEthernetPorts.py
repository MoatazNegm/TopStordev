#!/usr/bin/python3
import os, sys, subprocess, re
from time import time as stamp
import os, sys, subprocess, re
from time import time as stamp
from etcdput import etcdput as put
from etcdput import etcdput as put
from etcddel import etcddel as dels

def atoi(text):
    return int(text) if text.isdigit() else text

def natural_keys(text):
    '''
    alist.sort(key=natural_keys) sorts in human order
    http://nedbatchelder.com/blog/200712/human_sorting.html
    (See Toothy's implementation in the comments)
    '''
    return [ atoi(c) for c in re.split(r'(\d+)', text) ]

def dosync(sync,  *args):
  global leaderip, leader
  dels(leaderip, 'sync',sync)
  put(leaderip, *args)
  put(leaderip, args[0]+'/'+leader,args[1])
  return

def convertToDicts(data):
    keys = data[0].split()
    interfaces = []
    for values in data[1:]:
        if (values.replace(" ","") != ""):
            interface = dict(zip(keys,values.split()))
            interfaces.append(interface)
    return interfaces

def setInterfaces(*argv):
    cmdline = ['nmcli', 'device', 'status']
    result = subprocess.run(cmdline, stdout=subprocess.PIPE)
    availableInterfaces = str(result.stdout.decode()).replace('\n\n','n').split('\n')
    ethernetInterfaces = []
    for interface in convertToDicts(availableInterfaces):
        if (interface["TYPE"] == "ethernet" and not interface["DEVICE"].startswith('veth')):
            ethernetInterfaces.append(interface["DEVICE"])
    counter = 0
    ethernetInterfaces.sort(key=natural_keys)
    print(ethernetInterfaces)
    for interface in ethernetInterfaces:
        put(argv[0], 'ports/' + argv[2] + '/' + interface, 'eth' + str(counter))
        counter += 1
    stampit = str(stamp())
    dosync('ports_', 'sync/ports/add/request','ports_'+stampit)

if __name__=='__main__':
    global leaderip
    leaderip = sys.argv[1]
    leader = sys.argv[2]
    setInterfaces(*sys.argv[1:])
