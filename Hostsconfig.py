#!/usr/bin/python3
import subprocess,sys, datetime,socket
from etcdgetlocalpy import etcdget as get
from etcdget import etcdget as get2
from ast import literal_eval as mtuple

def getall(*bargs):
 with open('/root/tmp','w') as f:
   f.write('bargs'+str(bargs)+'\n')
 leader = get('leader')[0]
 leaderip = get('leaderip')[0]
 hosts = get('ready', '--prefix')
 allhosts= [] 
 hostsdict = dict()
 for host in hosts:
  hostname = host[0].replace('ready/','')
  hostip = host[1]
  ntp = get('ntp/'+hostname)[0]
  tz = get('tz/'+hostname)[0]
  gw = get('gw/'+hostname)[0]
  dnsname = get('dnsname/'+hostname)[0]
  dnssearch = get('dnssearch/'+hostname)[0]
  alias = get('alias/'+hostname)[0]
  ports = get2(leaderip,'ports/'+hostname,'--prefix')
  ports_raw = get2(leaderip, 'ports/' + hostname)[0]
  phy_ports = []
  if ports_raw and ports_raw != '_1':
   phy_ports = ports_raw.split('/')
  bond_data = get2(leaderip, 'bond', '--prefix')
  nmports = ""
  cmports = ""
  dports = ""
  iports = ""
  has_bond_config = False
  if bond_data:
   if len(bond_data) > 0:
    if bond_data[0] != '_1':
     has_bond_config = True
  if not has_bond_config:
   default_ports_str = ",".join(phy_ports)
   nmports = default_ports_str
   cmports = default_ports_str
   dports = default_ports_str
  else:
   for b in bond_data:
    if isinstance(b, (list, tuple)) and len(b) >= 2:
     b_key = b[0]
     b_val = b[1]
     val_clean = b_val.replace('/', ',') if b_val and b_val != '_1' else ""
     if 'nmports' in b_key:
      nmports = val_clean
     elif 'cmports' in b_key:
      cmports = val_clean
     elif 'dports' in b_key:
      dports = val_clean
     elif 'iports' in b_key:
      iports = val_clean
  try:
     ipaddrsubnet = get('ipaddr/'+hostname)[0].split('/')[1]
  except:
    ipaddrsubnet = '24'
  configured = get('configured/'+hostname)[0]
  if ipaddrsubnet == '_1':
   ipaddrsubnet = '24'
  if configured == '_1':
   configured = 'yes' 
  mgmt = get('namespace/mgmtip')[0] 
  isLeader = False
  if (hostname == leader):
    isLeader = True
  allhosts.append({"isLeader":isLeader, 'ports':ports,'name':hostname, 'configured':configured, 'alias':alias, 'ipaddr': hostip,'ipaddrsubnet':ipaddrsubnet, 'ntp':ntp, 'tz':tz, 'gw': gw,'dnsname':dnsname, 'dnssearch':dnssearch, 'cluster':mgmt, 'nmports': nmports, 'cmports': cmports, 'dports': dports, 'iports': iports})
  hostsdict[hostname] = {"isLeader":isLeader, 'ports':ports, 'configured':configured, 'alias':alias, 'ipaddr': hostip, 'ipaddrsubnet':ipaddrsubnet, 'ntp':ntp, 'tz':tz, 'gw': gw, 'dnsname':dnsname, 'dnssearch':dnssearch, 'cluster':mgmt, 'nmports': nmports, 'cmports': cmports, 'dports': dports, 'iports': iports }

 print(allhosts)
 return hostsdict 

if __name__=='__main__':
 getall(*sys.argv[1:])
