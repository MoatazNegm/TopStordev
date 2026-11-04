#!/usr/bin/python3
import sys, os, re
os.environ['ETCDCTL_API']= '3'
  
# QSD5.352 (QC 712): the read cache, the log and the spare devices of a pool are listed as raids named 'cache', 'logs',
# 'spares' (putzpool.py raid2).  They hold no data copies, so where they sit says nothing about the balance of the pool:
# a one-disk cache on one host got hostrank -1 and the pool card read 'Highly Available, not balanced' although every
# data raid spans both hosts.  They are ranked as balanced (0, 0) and the data raids decide.
AUXRAID = re.compile(r'^(cache|logs?|spares?)(_|$)')

def isauxraid(name):
 return bool(AUXRAID.match(str(name or '')))

def getraidrank(raid, removedisk, adddisk):
 ####raidraink = (name, location(0 is best), size (0) is best)
 if isauxraid(raid.get('name')):
  raid['raidrank'] = (0, 0)
  return raid
 raidrank = (0,0) 
 raidhosts = set()
 raiddsksize = adddisk['size']
 sizerank = 0
 hostdic = dict()
 raidlist = raid['disklist']
 if removedisk['name'] != adddisk['name']:
  raidlist = raidlist + list([adddisk]) 
 for disk in raidlist:
  if disk['name'] == removedisk['name'] and disk['name'] != adddisk['name']:
   continue
  if ('F' or 'moved') in disk['changeop'] :
   continue
  if disk['host'] not in hostdic:
   hostdic[disk['host']] = 0
  hostdic[disk['host']] += 1
  #raidhosts.add(disk['host'])
  if raiddsksize != disk['size']:
   sizerank = 1
 print('##################')
 print(hostdic)
 print(raid['name'])
 print(len(raid['disklist']+list([adddisk])))
 print('##################')
 hostset = set()
 hostrank = 0  
 for host in hostdic:
  hostset.add(hostdic[host])
 balance = len(raid['disklist'])%len(hostdic) 
 print('balance',balance)
 if balance == 0 and len(hostset) == 1 and len(hostdic) > 1:
  hostrank = 0
 else:
  hostrank = -1
 ###### ranking: no. of hosts differrence, and 1 for diff disk size found
 #hostrank = len(raidhosts)-len(raid['disklist'])
 raid['raidrank'] = (hostrank, sizerank)
 return raid 

  
 
 
if __name__=='__main__':
 getraidrank(*sys.argv[1:])
