#!/usr/bin/python3
import socket, subprocess,sys, datetime
from time import sleep
from logqueue import queuethis, initqueue
from etcdgetpy import etcdget as get
from etcdput import etcdput as put
from etcddel import etcddel as dels 
from broadcasttolocal import broadcasttolocal
from broadcast import broadcast
from ast import literal_eval as mtuple
from sendhost import sendhost
from UpdateNameSpace import updatenamespace
import logmsg
from time import time as stamp

def config(leader, leaderip, myhost, *bargs):
 arglist = bargs[0]
 initqueue(leaderip, myhost)
 logmsg.initlog(leaderip, myhost)
 #arglist = {'ipaddr': '10.11.11.123', 'ipaddrsubnet': '24', 'id': '0', 'user': 'admin', 'name': 'dhcp32502'}
 queuethis('Hostconfig','running',arglist)
 enpdev='enp0s8'
 needreboot=False
 for key in arglist:
  if arglist[key] == -1:
   arglist[key] = '-1'
 with open('/TopStordata/Hostconfig','w') as f:
  f.write(str(arglist)+'\n')
 stampi = str(stamp())
 ######### changing alias ###############
 if 'alias' in arglist:
  queuethis('Hostconfig_alias','running',arglist['user'])
  oldarg = str(get(leaderip, 'alias/'+arglist['name'])[0])
  logmsg.sendlog('HostManual1st5','info',arglist['user'],oldarg, arglist['alias'])
  allhosts = get(leaderip, 'ActivePartner','--prefix')
  put(leaderip, 'alias/'+arglist['name'],arglist['alias'])
  dels(leaderip, 'sync', 'alias_')
  put(leaderip, 'sync/alias/Add_'+arglist['name']+'_'+arglist['alias'].replace('_',':::').replace('/',':::')+'/request','alias_'+stampi)
  put(leaderip, 'sync/alias/Add_'+arglist['name']+'_'+arglist['alias'].replace('_',':::').replace('/',':::')+'/request/'+myhost,'alias_'+stampi)
  logmsg.sendlog('HostManual1su5','info',arglist['user'],oldarg, arglist['alias'])
  queuethis('Hostconfig_alias','finish',arglist['user'])
######### changing cluster address ###############
 if 'cluster' in arglist:
  queuethis('Hostconfig_cluster','running',arglist['user'])
  oldarg = str(get(leaderip, 'namespace/mgmtip')[0])
  logmsg.sendlog('HostManual1st7','info',arglist['user'],oldarg,arglist['cluster'])
#  broadcasttolocal('namespace/mgmtip',arglist['cluster'])
  leader = get(leaderip, 'leader')[0]
  #if myhost == leader:
  # updatenamespace(arglist['cluster'],oldarg)
  put(leaderip, 'namespace/mgmtip',arglist['cluster'])
  dels(leaderip, 'sync', 'namespace_')
  if 'ipaddr' not in arglist:
    put(leaderip, 'sync/namespace/Add_'+'namespace::mgmtip_'+arglist['cluster'].replace('/','::')+'/request','namespace_'+stampi)
  logmsg.sendlog('HostManual1su7','info',arglist['user'],oldarg,arglist['cluster'])
  queuethis('Hostconfig_cluster','finish',arglist['user'])

############ changing user password ###############
 if 'password' in arglist:
  if len(arglist['password']) < 3:
   logmsg.sendlog('Unlinfa12','error',arglist['user'],arglist['username'])
  else:
   print('changing password')
   queuethis('ChangeUserPass','running',arglist['user'])
   #broadcasttolocal('userhash/'+arglist['username'],arglist['password'])
   logmsg.sendlog('Unlin1012','info',arglist['user'],arglist['username'])
   cmdlinep=['/TopStor/encthis.sh',arglist['username'],arglist['password']]
   encthis=subprocess.run(cmdlinep,stdout=subprocess.PIPE).stdout.decode('utf-8').split('_result')[1]
   put(leaderip, 'usershash/'+arglist['username'], encthis)
   dels(leaderip, 'sync', 'passwd_')
   put(leaderip, 'sync/passwd/UnixChangePass_'+arglist['username']+'_'+arglist['user']+'/request','passwd_'+stampi)
   #put(leaderip, 'sync/passwd/UnixChangePass_'+arglist['username']+'_'+arglist['user']+'/request/'+myhost,'passwd_'+stampi)
#   broadcast('UserPassChange','/TopStor/pump.sh','UnixChangePass',arglist['password'],arglist['username'],arglist['user'])
   queuethis('ChangeUserPass','finish',arglist['user'])
############ changing time zone ###############
 if 'tz' in arglist:
  queuethis('Hostconfig_tzone','running',arglist['user'])
  oldarg = str(get(leaderip, 'tz/'+myhost)[0])
  argtz = arglist['tz'].split('%')[1]
  logmsg.sendlog('HostManual1st10','info',arglist['user'],oldarg, argtz)
  leader = get(leaderip, 'leader')[0]
  put(leaderip, 'tz/'+leader,arglist['tz'])
  dels(leaderip, 'sync', 'tz_')
  put(leaderip, 'sync/tz/HostManualconfigTZ_'+'_'+arglist['tz']+'/request','tz_'+stampi)
  logmsg.sendlog('HostManual1su10','info',arglist['user'], oldarg, argtz)
  queuethis('Hostconfig_tzone','finish',arglist['user'])
########### changing ntp server ###############
 if 'ntp' in arglist:
  queuethis('Hostconfig_ntp','running',arglist['user'])
  oldarg = str(get(leaderip, 'ntp/'+myhost)[0])
  logmsg.sendlog('HostManual1st9','info',arglist['user'],oldarg, arglist['ntp'])
  leader = get(leaderip, 'leader')[0]
  put(leaderip, 'ntp/'+leader,arglist['ntp'])
  dels(leaderip, 'sync', 'ntp_')
  put(leaderip, 'sync/ntp/HostManualconfigNTP_'+'_'+arglist['ntp']+'/request','ntp_'+stampi)
  logmsg.sendlog('HostManual1su9','info',arglist['user'],oldarg, arglist['ntp'])
  queuethis('Hostconfig_ntp','finish',arglist['user'])
########### changing dns  ###############
 if 'dnsname' in arglist:
  queuethis('Hostconfig_dns','running',arglist['user'])
  oldargname = str(get(leaderip, 'dnsname/'+myhost)[0])
  oldargsearch = str(get(leaderip, 'dnssearch/'+myhost)[0])
  if arglist['dnsname'] == "":
   arglist['dnsname'] = oldargname
  if arglist['dnssearch'] == "":
   arglist['dnssearch'] = oldargsearch
  logmsg.sendlog('HostManual1st13','info',arglist['user'],oldargname, oldargsearch, arglist['dnsname'],arglist['dnssearch'])
  leader = get(leaderip, 'leader')[0]
  put(leaderip, 'dnsname/'+leader,arglist['dnsname'])
  put(leaderip, 'dnssearch/'+leader,arglist['dnssearch'])
  dels(leaderip, 'sync', 'dns_')
  put(leaderip, 'sync/dns/HostManualconfigDNS'+'_'+arglist['dnsname']+'_'+arglist['dnssearch']+'/request','dns_'+stampi)
  logmsg.sendlog('HostManual1su13','info',arglist['user'],oldargname, oldargsearch, arglist['dnsname'],arglist['dnssearch'])
  queuethis('Hostconfig_dns','finish',arglist['user'])
 
########### changing gateway  ###############
 if 'gw' in arglist:
  queuethis('Hostconfig_gw','running',arglist['user'])
  oldarg = str(get(leaderip, 'gw/'+myhost)[0])
  logmsg.sendlog('HostManual1st11','info',arglist['user'],oldarg, arglist['gw'])
  leader = get(leaderip, 'leader')[0]
  put(leaderip, 'gw/'+leader,arglist['gw'])
  dels(leaderip, 'sync', 'gw_')
  put(leaderip, 'sync/gw/HostManualconfigGW_'+'_'+arglist['gw']+'/request','gw_'+stampi)
  logmsg.sendlog('HostManual1su11','info',arglist['user'],oldarg, arglist['gw'])
  queuethis('Hostconfig_gw','finish',arglist['user'])
 ############# changing configured  ###############
 if 'configured' in arglist:
  print('chaning configured status')
  queuethis('Hostconfig_cf','running',arglist['user'])
  if 'yes' in arglist['configured']:
   logmsg.sendlog('HostManual1st12','info',arglist['user'])
  else:
   logmsg.sendlog('HostManual2st12','info',arglist['user'])
  put(leaderip, 'configured/'+arglist['name'],arglist['configured'])
  dels(leaderip, 'sync/cf', 'confiugred_'+arglist['name'])
  put(leaderip, 'sync/cf/HostManualconfigCF_'+'_'+arglist['name']+'/request','configured_'+arglist['name']+'_'+stampi)
  if 'yes' in arglist['configured']:
   logmsg.sendlog('HostManual1su12','info',arglist['user'])
  else:
   logmsg.sendlog('HostManual2su12','info',arglist['user'])
  queuethis('LocalManualConfig.py','stop',bargs[-1])
 ########## changing box address ###############
 if 'ipaddr' in arglist:
  print('changin the ipaddress of the node')
  queuethis('Hostconfig_ip','running',arglist['user'])
  oldipaddr = str(get(leaderip, 'ipaddr/'+arglist['name'])[0])
  logmsg.sendlog('HostManual1st6','info',arglist['user'],str(oldipaddr),arglist['ipaddr']+'/'+arglist['ipaddrsubnet'])
  put(leaderip, 'ipaddr/'+arglist['name'],arglist['ipaddr']+'/'+arglist['ipaddrsubnet'])
  dels(leaderip, 'sync', 'ActivePartners_'+arglist['name'])
  dels(leaderip, 'ActivePartners/'+arglist['name'])
  cmdline = '/TopStor/promserver.sh '+leaderip
  subprocess.run(cmdline.split(),stdout=subprocess.PIPE)
  put(leaderip, 'ActivePartners/'+arglist['name'],arglist['ipaddr'])
  dels(leaderip, 'sync', 'ipaddr_'+arglist['name'])
  if 'cluster' not in arglist:
    put(leaderip, 'sync/ipaddr/HostManualconfigIPADDR_'+'_'+arglist['name']+'/request','ipaddr_'+arglist['name']+'_'+stampi)
  else:
    put(leaderip, 'sync/cluip/HostManualconfigCLUIP_'+'_'+arglist['name']+'/request','ipaddr_'+arglist['name']+'_'+stampi)
    
  put(leaderip, 'sync/ipaddr/Add_ActivePartners_'+arglist['name']+'_'+arglist['ipaddr'].replace('/','::')+'/request','ActivePartners_'+arglist['name']+'_'+stampi)

  put(leaderip, 'sync/ipaddr/Add_ActivePartners_'+arglist['name']+'_'+arglist['ipaddr'].replace('/','::')+'/request/'+leader,'ActivePartners_'+arglist['name']+'_'+stampi)
  logmsg.sendlog('HostManual1su6','info',arglist['user'], str(oldipaddr),arglist['ipaddr']+'/'+arglist['ipaddrsubnet'])
  queuethis('Hostconfig_ip','finish',arglist['user'])
######################################
 queuethis('Hostconfig','finish',arglist)
 return 1






if __name__=='__main__':
 leaderip = sys.argv[1]
 leader = get(leaderip, 'leader')[0]
 leaderip = get(leaderip, 'leaderip')[0]
 myhost = leader
 #arg = {'username': 'admin', 'password': 'YousefNadody', 'token': '4f3223c155ca50d13ae975ea18e930bc', 'response': 'admin', 'user': 'admin'}
 arg = {'dnsname': '10.11.11.11', 'dnssearch': 'qstor.com', 'id': '0', 'user': 'admin', 'name': 'dhcp14895', 'token': 'e9b77595837168e6f0ce77f6cbc8137e', 'response': 'admin'}
 arg = {'alias': 'Repli_1', 'ipaddr': '10.11.11.245', 'ipaddrsubnet': '24', 'cluster': '10.11.11.249/24', 'tz': 'Kuwait%(GMT+03!00)_Kuwait^_Riyadh^_Baghdad', 'id': '0', 'user': 'admin', 'name': 'dhcp28109', 'token': '73616fae666891c5f420f63c6317b1ba', 'response': 'admin'}
 arg={'alias': 'node_2', 'id': '0', 'user': 'admin', 'name': 'dhcp141762', 'token': '7aaffece0d6602393b42b5ef34164c8b', 'response': 'admin'}
 arg={'cluster': '10.11.11.252/24', 'id': '0', 'user': 'admin', 'name': 'dhcp207722', 'token': '2f9124d029074800677590f565c7cb5a', 'response': 'admin'}
 arg={'ipaddr': '10.11.11.240', 'ipaddrsubnet': '24', 'id': '0', 'user': 'admin', 'name': 'dhcp207722', 'token': 'c20580a16e1c42a2d63f68719ab40ea9', 'response': 'admin'}
 arg={'ipaddr': '10.11.11.240', 'ipaddrsubnet': '24', 'id': '0', 'user': 'admin', 'name': 'dhcp207722', 'token': '9df4c7384591ccb9e699d0c4ec4321ac', 'response': 'admin'}
 arg={'ipaddr': '10.11.11.241', 'ipaddrsubnet': '24', 'id': '0', 'user': 'admin', 'name': 'dhcp250171', 'token': '869927c8ed2149878087f60124fe148a', 'response': 'admin'}
 arg={'username': 'rezo', 'password': '111', 'user': 'admin'}
 arg={'alias': 'node_2', 'ipaddr': '10.11.11.102', 'ipaddrsubnet': '24', 'cluster': '10.11.11.100/24', 'tz': 'Kuwait%(GMT+03!00)_Kuwait^_Riyadh^_Baghdad', 'id': '0', 'user': 'admin', 'name': 'dhcp142412', 'token': '19cafd4f6fac19f9dfe4ef8f03ee8375', 'response': 'admin'}
 arg={'username': 'user1', 'password': '15dlksdkdj34', 'user': 'admin'}
 config(leader, leaderip, myhost, arg)

#{'cluster': '10.11.11.250/24', 'tz': 'Kuwait%(GMT+03!00)_Kuwait^_Riyadh^_Baghdad', 'id': '0', 'user': 'admin', 'name': 'dhcp32570', 'token': '501ef1257322d1814125b1e16af95aa9', 'response': 'admin'}
