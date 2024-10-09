#!/usr/bin/python3
import flask, os, Evacuate, subprocess, Joincluster, sys, re
from getversions import getversions
from functools import wraps
from copy import deepcopy
from flask import request, jsonify, render_template, redirect, url_for, g, send_file
import re, ipaddress
import Hostsconfig
from Hostconfig import config
from allphysicalinfo import getall 
from UnixChkUser import setlogin
import sqlite3
from etcdget2 import etcdgetjson
from etcdgetlocalpy import etcdget  as get
from etcddellocal import etcddel  as dels 
from sendhost import sendhost
from socket import gethostname as hostname
from getlogs import getlogs, onedaylog
from fapistats import allvolstats, dskperf, cpuperf
from datetime import datetime
from getallraids import newraids
from fastselect import selectdisks
from secrets import token_hex
from ioperf import ioperf
from time import time as timestamp
import logmsg
from collectNodeConfig import getConfig, downloadConfig
import zipfile
from time import sleep

getalltimestamp = 0
os.environ['ETCDCTL_API'] = '3'
loggedusers = {}
alldsks = []
allpools = 0
allgroups = []
allvolumes = []
allusers = []
readyhosts = []
activehosts = []
losthosts = []
possiblehosts = []
pooldict = dict()
app = flask.Flask(__name__)
app.config["DEBUG"] = True
logcatalog = ''
with open('/TopStor/msgsglobal.txt') as f:
 logcatalog = f.read().split('\n')
logdict = dict()
for log in logcatalog:
 msgcode= log.split(':')[0]
 logdict[msgcode] = log.replace(msgcode+':','').split(' ')
allinfo = 0

def is_valid_ip(ip):
    try:
        ipaddress.ip_address(ip)
        return 0 
    except ValueError:
        return 10 


def is_unique_ip(ip, vtype='NZ#@A' ):
        global leaderip
        allvols = get('vol', '--prefix')
        allvols = [x for x in allvols if vtype not in str(x)]
        allvols = str(allvols)
        allnodes= get('Active','--prefix')
        allnodes = str(allnodes)
        allpartners= get('Partner','--prefix')
        allpartners = str(allpartners)
        allips = allvols+'/'+leaderip+'/'+allnodes+'/'+allpartners
        ip_pattern = rf'\b{re.escape(ip)}\b' 
        if bool(re.search(ip_pattern,allips)):
                    print("Invalid IP")
                    return 100 
        print("Valid IP")
        return 0 

def is_unique_name(name):
        global leaderip
        allvols = str(get('vol', '--prefix'))
        alluser= str(get('user','--prefix'))
        allgrp= str(get('group','--prefix'))
        allnames = allvols+'/'+alluser+'/'+allgrp
        name_pattern = rf'\b{re.escape(name)}\b' 
        if bool(re.search(name_pattern,allnames)):
                    print("Invalid Name")
                    return 1000 
        print("Valid Name")
        return 0 



def getalltime(renew='no'):
 global allinfo,alldsks, getalltimestamp, leaderip
 #if (getalltimestamp+30) < timestamp() or renew == 'yes':
 if (getalltimestamp+1) < timestamp() or renew == 'yes':
  alldsks = deepcopy(get('host','current'))
  allinfo = deepcopy(getall(leaderip, alldsks))
  getalltimestamp = timestamp()
 return
def login_required(f):
 @wraps(f)
 def decorated_function(*args, **kwargs):
  data = request.args.to_dict()
  for dat in data:
    data[dat] = data[dat].replace(' ','')
  data['response'] = 'baduser'
  if data['token'] in loggedusers:
   if loggedusers[data['token']]['timestamp'] > timestamp():
    data['user'] = loggedusers[data['token']]['user']
    data['response'] = data['user'] 
    return f(data)
   else:
    logmsg.sendlog('Lognsa0','warning','system',loggedusers[data['token']]['user'])
  else:
   logmsg.sendlog('Lognno0','warning','system',data['token'])
  return f({'response':'baduser'})
 return decorated_function

@app.route('/api/v1/users/uploadUsers', methods=['GET','POST'])
@login_required
def uploadUsers(data):
    global allgroups, leaderip, myhost
    if 'baduser' in data['response']:
      return {'response': 'baduser'}
    uploaded_file = request.files['file']
    if uploaded_file.filename != '':
      dirPath = '/TopStordata'
      isExist = os.path.exists(dirPath)
      if not isExist:
        os.makedirs(dirPath)
      filename =  uploaded_file.filename.replace(' ', '')
      filePath = os.path.join(dirPath, filename)
      uploaded_file.save(filePath)
      cmdline = 'python /TopStor/UsersMassAddition.py '+ leaderip +' '+ data['user'] + ' ' + myhost + ' ' + filePath
      postchange(cmdline)
      logmsg.sendlog('Unlin1025', 'info', data["user"])
      return {"data":data}
    else:
      logmsg.sendlog('Unlin1026', 'error', data["user"])
      return 'Error while uploading file!'


def postchange(cmndstring,host='myhost'):
 global leaderip, myhost
 if host=='myhost':
  host = myhost
 z= cmndstring.split(' ')
 msg={'req': 'Pumpthis', 'reply':z}
 ownerip=get('ready/'+host,'--prefix')
 #with open('/TopStor/tempdata','w') as f:
 # f.write(str((ownerip[0][1], str(msg),'recvreply',myhost)))
 sendhost(ownerip[0][1], str(msg),'recvreply',myhost)

def dict_factory(cursor, row):
    d = {}
    for idx, col in enumerate(cursor.description):
        d[col[0]] = row[idx]
    return d

def getusers():
 global leaderip
 userlst = etcdgetjson(leaderip,'usersinfo','--prefix') 
 uid = 0
 users = []
 for user in userlst:
  username = user['name'].replace('usersinfo/','')
  users.append([username,str(uid)]) 
  uid += 1
 return users

def getgroups():
 global leaderip
 groupslst = etcdgetjson(leaderip, 'usersigroup','--prefix') 
 gid = 0
 groups = []
 for group in groupslst:
  grpusers = group['prop'].split('/')[2]
  groupname = group['name'].replace('usersigroup/','')
  groups.append([groupname,str(gid), grpusers]) 
  gid += 1
 return groups

@app.route('/', methods=['GET'])
def home():
    return '''<h1>Distant Reading Archive</h1>
<p>A prototype API for distant reading of science fiction novels.</p>'''

def getpools():
 global pooldict, leaderip
 pools = get('pools/','--prefix')
 poolinfo = []
 pid = 0
 for pool in pools:
  poolinfo.append({'id':pid, 'owner': pool[1], 'text':pool[0].split('/')[1]})
  pid += 1
  pooldict[pool[0].split('/')[1]] = {'id': pid, 'owner': pool[1] }
 return poolinfo

@app.route('/api/v1/volumes/connections', methods=['GET','POST'])
@login_required
def getconns(data):
 global leaderip
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 conns = get('connections/user','--prefix')
 devs = get('connections/dev','--prefix')
 zippedconns = zip(conns,devs)
 conndict =  {}
 conndict['connections'] = []
 tconns = 0
 for conn in zippedconns:
  volume = conn[0][0].split('/')[3]
  subconns =  conn[0][1].split('/')
  subdevs =  conn[1][1].split('/')
  zippedsubconns = zip(subconns,subdevs)
  for subcon in zippedsubconns:
   conndict['connections'].append({"volume": volume, 'user': subcon[0], 'device':subcon[1] })
 conndict['response'] = data['response']
 return conndict 


@app.route('/api/v1/software/setversion', methods=['GET','POST'])
@login_required
def setversion(data):
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 versions = getversions()
 if data['version'] in versions['versions'] and data['version'] not in versions['current']:
  cmdline = '/TopStor/updateversion '+data['version']
  postchange(cmdline)
 return data 

@app.route('/api/v1/software/versions', methods=['GET','POST'])
@login_required
def versions(data):
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 return getversions()

#@app.route('/api/v1/hosts/info', methods=['GET','POST'])
def hostsinfo():
 global allhosts, readyhosts, activehosts, losthosts, possiblehosts
 allhosts = Hostsconfig.getall()
 return jsonify(allhosts)

@app.route('/api/v1/hosts/allinfo', methods=['GET','POST'])
@login_required
def hostsallinfo(data):
 global allhosts, readyhosts, activehosts, losthosts, possiblehosts
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 hostsinfo()
 hostslost()  
 hostspossible()
 return jsonify({'all': allhosts, 'active': activehosts, 'ready':readyhosts, 'possible':possiblehosts, 'lost':losthosts})


#@app.route('/api/v1/hosts/ready', methods=['GET','POST'])
def hostsready():
 global allhosts, readyhosts, activehosts, losthosts, possiblehosts, leaderip
 hosts = get('ready','--prefix')
 readyhosts = []
 hid = 0
 for host in hosts:
  name = host[0].replace('ready/','')
  ip = host[1]
  readyhosts.append({'name':name, 'ip': ip, 'id': hid}) 
  hid +=1
 return jsonify(readyhosts)

#@app.route('/api/v1/hosts/active', methods=['GET','POST'])
def hostsactive():
 global allhosts, readyhosts, activehosts, losthosts, possiblehosts, leaderip
 hosts = get('ActivePartners','--prefix')
 activehosts = []
 hid = 0
 for host in hosts:
  name = host[0].replace('ActivePartners/','')
  ip = host[1]
  activehosts.append({'name':name, 'ip': ip, 'id': hid}) 
  hid +=1
 return jsonify(activehosts)


@app.route('/api/v1/hosts/discover', methods=['GET','POST'])
@login_required
def discover(data):
    if 'baduser' in data['response']:
      return {'response': 'baduser'}
    cmndstring = '/TopStor/getdiscovery.sh '
    postchange(cmndstring)
    return data 

#@app.route('/api/v1/hosts/possible', methods=['GET','POST'])
def hostspossible():
 global allhosts, readyhosts, activehosts, losthosts, possiblehosts, leaderip
 hosts = get('possible','--prefix')
 possiblehosts = []
 hid = 0
 for host in hosts:
  name = host[0].split('/')[1]
  ip = host[1]
  possiblehosts.append({'name':name, 'ip': ip, 'id': hid}) 
  hid +=1
 return jsonify(possiblehosts)

#@app.route('/api/v1/hosts/lost', methods=['GET','POST'])
def hostslost():
 global allhosts, readyhosts, activehosts, losthosts, possiblehosts
 hostsready()
 hostsactive()
 losthosts = []
 hid = 0
 for active in activehosts:
  if active['name'] not in str(readyhosts): 
   losthosts.append({'id': hid, 'name': active['name'], 'ip': active['ip']})
  hid += 1
 return jsonify(losthosts)

@app.route('/api/v1/pools/dgsinfo', methods=['GET','POST'])
@login_required
def dgsinfo(data):
 global allinfo 
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 getalltime()
 dgsinfo = {'raids':allinfo['raids'], 'pools':allinfo['pools'], 'disks':allinfo['disks']}
 dgsinfo['newraid'] = newraids(allinfo['disks'])
 return jsonify(dgsinfo)

@app.route('/api/v1/pools/delpool', methods=['GET','POST'])
@login_required
def dgsdelpool(data):
 global allinfo, myhost
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 getalltime()
 owner = allinfo['pools'][data['pool']]['host']
 ownerip = allinfo['hosts'][owner]['ipaddress']
 datastr = data['pool']+' '+data['user'] 
 cmndstring = '/TopStor/DGdestroyPool '+leaderip+' '+datastr
 z= cmndstring.split(' ')
 msg={'req': 'Pumpthis', 'reply':z}
 sendhost(ownerip, str(msg),'recvreply',myhost)
 return jsonify(data)

@app.route('/api/v1/pools/addtopool', methods=['GET','POST'])
@login_required
def dgsaddtopool(data):
 global allinfo, myhost, leaderip
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 getalltime('yes')
 keys = []
 dgsinfo = {'raids':allinfo['raids'], 'pools':allinfo['pools'], 'disks':allinfo['disks']}
 dgsinfo['newraid'] = newraids(allinfo['disks'])
 if data['useable'] not in dgsinfo['newraid'][data['redundancy']]:
  keys = list(dgsinfo['newraid'][data['redundancy']].keys())
  keys.append(float(data['useable']))
  keys.sort()
  diskindx = keys.index(float(data['useable'])) + 1
  if diskindx == len(keys):
   diskindx = len(keys) - 2 
  data['useable'] = keys[diskindx]
 disks =  dgsinfo['newraid'][data['redundancy']][data['useable']]
 if 'single' in data['redundancy']:
  selecteddisks= disks
 else:
  print('#########################')
  print('disks',disks)
  print('#########################')
  bestdisks = selectdisks(leaderip,disks,allinfo['disks'],data['pool'])
  print('bestdisks',bestdisks)
  print('#########################')
 if len(bestdisks) < 1:
    return jsonify(data)
 selecteddisks = bestdisks.split(',')
 owner = allinfo['pools'][data['pool']]['host']
 ownerip = allinfo['hosts'][owner]['ipaddress']
 diskstring = ''
 for dsk in selecteddisks:
  diskstring += dsk+":"+dsk[-5:]+" "
 if 'mirror' in data['redundancy']:
  datastr = 'addmirror '+data['user']+' '+owner+" "+diskstring+data['pool']
 elif 'volset' in data['redundancy']:
  datastr = 'addstripeset '+data['user']+' '+owner+" "+diskstring+data['pool']
 elif 'raid5' in data['redundancy']:
  datastr = 'addparity '+data['user']+' '+owner+" "+diskstring+data['pool']
 elif 'raid6plus' in data['redundancy']:
  datastr = 'addparity3 '+data['user']+' '+owner+" "+diskstring+data['pool']
 elif 'raid6' in data['redundancy']:
  datastr = 'addparity2 '+data['user']+' '+owner+" "+diskstring+data['pool']
 cmndstring = '/TopStor/DGsetPool '+leaderip+' '+datastr
 z= cmndstring.split(' ')
 msg={'req': 'Pumpthis', 'reply':z}
 sendhost(ownerip, str(msg),'recvreply',myhost)
 return jsonify(data)
 

@app.route('/api/v1/pools/newpool', methods=['GET','POST'])
@login_required
def dgsnewpool(data):
 global allinfo, myhost, leaderip
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 getalltime('yes')
 keys = []
 dgsinfo = {'raids':allinfo['raids'], 'pools':allinfo['pools'], 'disks':allinfo['disks']}
 dgsinfo['newraid'] = newraids(allinfo['disks'])
 if data['useable'] not in dgsinfo['newraid'][data['redundancy']]:
  keys = list(dgsinfo['newraid'][data['redundancy']].keys())
  keys.append(float(data['useable']))
  keys.sort()
  diskindx = keys.index(float(data['useable'])) + 1
  if diskindx == len(keys):
   diskindx = len(keys) - 2 
  data['useable'] = keys[diskindx]
 disks =  dgsinfo['newraid'][data['redundancy']][data['useable']]
 if 'single' in data['redundancy']:
  selecteddisks= disks
 else:
  bestdisks = selectdisks(leaderip, disks, allinfo['disks'])
  if len(bestdisks) < 1:
    return jsonify(data)
  selecteddisks = bestdisks.split(',')
 diskstring = ''
 for dsk in selecteddisks:
  diskstring += dsk+":"+dsk[-5:]+" "
 print('#############################3')
 print(';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;')
 print(selecteddisks)
 print('#########################333')
 owner = allinfo['disks'][selecteddisks[0]]['host']
 ownerip = allinfo['hosts'][owner]['ipaddress']
 if 'single' in data['redundancy']:
  datastr = 'Single '+data['user']+' '+owner+" "+selecteddisks[0]+" "+selecteddisks[0][-5:]+" nopool "+data['user']+" "+owner
 elif 'mirror' in data['redundancy']:
  datastr = 'mirror '+data['user']+' '+owner+" "+diskstring+"nopool "+data['user']+" "+owner
 elif 'volset' in data['redundancy']:
  datastr = 'stripeset '+data['user']+' '+owner+" "+diskstring+" "+data['user']+" "+owner
 elif 'raid5' in data['redundancy']:
  datastr = 'parity '+data['user']+' '+owner+" "+diskstring
 elif 'raid6plus' in data['redundancy']:
  datastr = 'parity3 '+data['user']+' '+owner+" "+diskstring+" "+data['user']+" "+owner
 elif 'raid6' in data['redundancy']:
  datastr = 'parity2 '+data['user']+' '+owner+" "+diskstring+" "+data['user']+" "+owner
 cmndstring = '/TopStor/DGsetPool '+leaderip+' '+datastr+' '+data['user']
 z= cmndstring.split(' ')
 msg={'req': 'Pumpthis', 'reply':z}
 sendhost(ownerip, str(msg),'recvreply',myhost)
 return jsonify(data)
 

@app.route('/api/v1/volumes/stats', methods=['GET','POST'])
@login_required
def volumestats(data):
 global allinfo 
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 getalltime()
 volstats = allvolstats(leaderip, deepcopy(allinfo))
 return jsonify(volstats)

@app.route('/api/v1/volumes/volumelist', methods=['GET','POST'])
@login_required
def volumeslist(data):
 global allinfo 
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 getalltime()
 volumes = []
 vid = 0
 for vol in allinfo['volumes']:
  volumes.append({'id':vid, 'text':vol.split('_')[0], 'fullname':vol,'pool':allinfo['volumes'][vol]['pool']})
  vid += 1
 return jsonify(volumes)



@app.route('/api/v1/volumes/poolsinfo', methods=['GET','POST'])
@login_required
def volpoolsinfo(data):
 global allpools
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 allpools = getpools()
 return jsonify({'results':allpools})

@app.route('/api/v1/stats/dskperf', methods=['GET','POST'])
def dskperfs():
 #ioperf(leaderip,myhost)
 global leaderip
 return jsonify({'dsk':dskperf(leaderip), 'cpu':cpuperf(leaderip)})


@app.route('/api/v1/volumes/snapshots/snapshotsinfo', methods=['GET','POST'])
@login_required
def volumessnapshotsinfo(data):
 global allvolumes, alldsks, allinfo
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 snaplist = {'Once':[], 'Minutely': [], 'Hourly': [], 'Weekly':[], '-':[]}
 periodlist = {'Minutely': [], 'Hourly': [], 'Weekly':[], 'Trend': []}
 getalltime()
 allgroups = getgroups()
 alllist = []
 snappriods = []
 for snap in allinfo['snapshots']:
  allinfo['snapshots'][snap]['date'] = datetime.strptime(allinfo['snapshots'][snap]['creation'], '%a %b %d %Y').strftime('%d-%B-%Y')
  print('#####################################33')
  print(allinfo['snapshots'][snap])
  print('#####################################33')
  snaplist[allinfo['snapshots'][snap]['snaptype']].append(allinfo['snapshots'][snap].copy())
  alllist.append(allinfo['snapshots'][snap].copy())
 for period in allinfo['snapperiods']:
  snappriods.append(allinfo['snapperiods'][period].copy())
  periodlist[allinfo['snapperiods'][period]['periodtype']].append(allinfo['snapperiods'][period].copy())
 return jsonify({'allsnaps':alllist, 'Once':snaplist['Once'], 'Hourly':snaplist['Hourly'], 'Weekly':snaplist['Weekly'], 'Minutely':snaplist['Minutely'] ,'allperiods':snappriods, 'Minutelyperiod':periodlist['Minutely'], 'Hourlyperiod':periodlist['Hourly'], 'Weeklyperiod':periodlist['Weekly']})

def volumesinfo(prot='all'):
 global allvolumes, alldsks, allinfo
 getalltime()
 allgroups = getgroups()
 volgrouplist = []
 volumes = []
 if prot == 'all':
   prot = 'S'
   prot2 = 'H'
 else:
  prot2 = prot
 for volume in allinfo['volumes']:
  if prot in allinfo['volumes'][volume]['prot'] or prot2 in allinfo['volumes'][volume]['prot']:
   volgrps = []
   if prot in ['CIFS','NFS']:
    print('##################')
    print(allinfo['volumes'][volume])
    print('##################')
    try:
        volgrouplist =  deepcopy(allinfo['volumes'][volume]['groups'])
    except:
        volgrouplist=[]
    if type(volgrouplist) != list:
      volgrouplist = volgrouplist.split(',')
    for group in allgroups:
     if group[0] in volgrouplist:
      volgrps.append(group[1])
   volumes.append(deepcopy(allinfo['volumes'][volume]))
   volumes[-1]['groups'] = deepcopy(volgrps)
 return volumes


@app.route('/api/v1/volumes/CIFS/volumesinfo', methods=['GET','POST'])
@login_required
def volumescifsinfo(data):
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 volumes = volumesinfo('CIFS') 
 return jsonify({'allvolumes':volumes})

@app.route('/api/v1/volumes/ISCSI/volumesinfo', methods=['GET','POST'])
@login_required
def volumesiscsiinfo(data):
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 volumes = volumesinfo('ISCSI') 
 return jsonify({'allvolumes':volumes})

@app.route('/api/v1/volumes/NFS/volumesinfo', methods=['GET','POST'])
@login_required
def volumesnfsinfo(data):
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 volumes = volumesinfo('NFS') 
 return jsonify({'allvolumes':volumes})

@app.route('/api/v1/volumes/HOME/volumesinfo', methods=['GET','POST'])
@login_required
def volumeshomeinfo(data):
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 volumes = volumesinfo('HOME') 
 return jsonify({'allvolumes':volumes})

@app.route('/api/v1/volumes/volumesinfo', methods=['GET','POST'])
@login_required
def volumesallinfo(data):
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 volumes = volumesinfo() 
 return jsonify({'allvolumes':volumes})



@app.route('/api/v1/pools/poolsinfo', methods=['GET','POST'])
@login_required
def poolsinfo(data):
 global allpools
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 allpools = getpools()
 allpools.append({'id':len(allpools), 'text':'-------'})
 return jsonify({'results':allpools})

@app.route('/api/v1/groups/groupchange', methods=['GET','POST'])
@login_required
def pgroupchange(data):
 global leaderip
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 usrs = data.get('users')
 usrstr = ''
 if len(usrs) < 1:
  usrstr = 'NoUser'
 else:
  for usr in usrs.split(','):
   for suser in allusers:
    if str(suser['id']) == str(usr):
     usrstr += suser['name']+',' 
  usrstr = usrstr[:-1]
 cmndstring = '/TopStor/UnixChangeGroup '+leaderip+' '+' '+data.get('name')+' users'+usrstr+' '+data['user']+' '+'change'
 postchange(cmndstring)
 return data

@app.route('/api/v1/replication/addpartner', methods=['GET','POST'])
@login_required
def partneradd(data):
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 cmndstring = '/TopStor/PartnerAdd.py '+data.get('partnerip')+' '+data.get('partneralias')+' '+data.get('replitype')+' '+data.get('repliport')+' '+data.get('phrase')+' '+data.get('user')
 postchange(cmndstring)
 return data

@app.route('/api/v1/users/userchange', methods=['GET','POST'])
@login_required
def userchange(data):
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 grps = data.get('groups')
 groupstr = ''
 allgroups = getgroups()
 if len(grps) < 1:
  groupstr = 'NoGroup'
 else:
  for grp in grps.split(','):
   groupstr += allgroups[int(grp)][0]+','
  groupstr = groupstr[:-1]
 cmndstring = '/TopStor/UnixChangeUser '+leaderip+' '+data.get('name')+' groups'+groupstr+' '+data['user']+' '+'change'
 postchange(cmndstring)
 return data

 
@app.route('/api/v1/info/onedaylog', methods=['GET','POST'])
@login_required
def getonedaylog(data):
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 result = onedaylog() 
 return result 
@app.route('/api/v1/info/logs', methods=['GET','POST'])
@login_required
def getalllogs(data):
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 notif = getlogs()
 return jsonify({'alllogs': notif})


@app.route('/api/v1/login/renewtoken', methods=['GET','POST'])
@login_required
def renewtoken(data):
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 user = loggedusers[data['token']]['user']
 setlogin(leaderip,myhost, user,'!',data['token'])
 return data


@app.route('/api/v1/info/cversion', methods=['GET','POST'])
@login_required
def getcversion(data):
    global leaderip, leader, myhost
    if 'baduser' in data['response']:
      return {'response': 'baduser'}
    cmdline='/TopStor/getcversion.sh '+leaderip+' '+leader+' '+myhost
    #subprocess.run(cmdline,stdout=subprocess.PIPE)
    postchange(cmdline)
    cversions = get('cversion/'+myhost)[0]
    return { 'response':'Ok', 'cversion': str(cversions)}



@app.route('/api/v1/info/notification', methods=['GET','POST'])
@login_required
def getnotification(data):
 global leaderip, myhost
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 notifbody = get('notification')[0].split(' ')[1:]
 isinsync = get('isinsync')[0]
 with open('/root/tmptmp','a') as f:
    f.write(str(notifbody))
 requests = get('request','--prefix')
 requestdict = {}
 for req in requests:
  reqname = req[0].split('/')[1]
  reqhost = req[0].split('/')[2]
  reqstatus = req[1]
  if reqname not in requestdict:
   requestdict[reqname] = {}
  requestdict[reqname][reqhost] = reqstatus
 try:
    msg = logdict[notifbody[3]]
 except:
    msg = logdict['NotSupported']
    logmsg.sendlog('NotSupported','warning','system',str(notifbody))
    return { 'isinsync': isinsync, 'response': 'Ok' }
    
   
 msgbody = '.'
 notifc = 6
 for word in msg[4:]:
  if word == ':':
   try:
    msgbody = msgbody[:-1]+' '+notifbody[notifc]+'.'
   except:
    msgbody = str(msgbody) +' '+str(notifbody)+'parseerror.'
    with open('/root/fapierror','w') as f:
     f.write(msgbody+'\n'+str(msg))
    print('notification parse error')
    print('############################')
   notifc += 1
  elif len(word) > 0:
   msgbody = msgbody[:-1]+' '+word+'.' 
 notif = { 'isinsync': isinsync, 'importance':msg[0].replace(':',''), 'msgcode': notifbody[3], 'date':notifbody[0], 'time':notifbody[1],
	 'host':notifbody[2], 'type':notifbody[4], 'user': notifbody[5], 'msgbody': msgbody[1:],'requests':requestdict, 'response':'Ok'}
 return jsonify(notif)

@app.route('/api/v1/volumes/snapshots/create', methods=['GET','POST'])
@login_required
def volumesnapshotscreate(data):
 global allinfo, myhost
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 datastr = ''
 getalltime()
 ownerip = allinfo['hosts'][data['owner']]['ipaddress']
 data['leaderip'] = leaderip
 switch = { 'Once':['snapsel','leaderip', 'name','pool','volume'], 'Minutely':['snapsel', 'leaderip', 'pool', 'volume', 'every', 'keep'],
	'Hourly':['snapsel', 'leaderip', 'pool', 'volume', 'sminute', 'every', 'keep'], 
	'Weekly':['snapsel', 'leaderip', 'pool', 'volume', 'stime', 'every', 'keep'] }
 datastr = ''
 for param in switch[data['snapsel']]:
  datastr +=data[param]+' '
 #datastr = data['name']+' '+data['pool']+' '+data['volume']+' '+data['user']
 if 'receiver' not in data:
   datastr += 'NoReceiver'
 else:
   datastr += data['receiver']
 print('#############################')
 print(data)
 print(datastr)
 print('###########################')
 cmndstring = '/TopStor/SnapshotCreate'+datastr+' '+data['user']
 z= cmndstring.split(' ')
 msg={'req': 'Pumpthis', 'reply':z}
 sendhost(ownerip, str(msg),'recvreply',myhost)
 return data





@app.route('/api/v1/volumes/create', methods=['GET','POST'])
@login_required
def volumecreate(data):
 global allinfo, myhost
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 datastr = ''
 isvu =  int(is_valid_ip(data['ipaddress']))+int(is_unique_ip(data['ipaddress'],data['type']))+int(is_unique_name(data['name']))
 if isvu == 0:
    print('ip is valid')
 else:
    if isvu < 100:
        logmsg.sendlog('IPaddrfa','error','system',loggedusers[data['token']]['user'])
    elif isvu > 10 and isvu < 120: 
        logmsg.sendlog('IPadduqfa','error','system',loggedusers[data['token']]['user'])
    else:
        logmsg.sendlog('IPnamuqfa','error','system',loggedusers[data['token']]['user'])
    return data
 getalltime()
 ownerip = allinfo['hosts'][allinfo['pools'][data['pool']]['host']]['ipaddress']
 data['owner'] = allinfo['hosts'][allinfo['pools'][data['pool']]['host']]['name']
 if 'ISCSI' in data['type']:
  data['chapuser']='MoatazNegm'
  data['chappas']='MezoAdmin'
  datastr = data['pool']+' '+data['name']+' '+data['size']+' '+data['ipaddress']+' '+data['Subnet']+' '+data['portalport']+' '+data['initiators']+' '+data['chapuser']+' '+data['chappas']+' '+data['active']+' '+data['user']+' '+data['owner']+' '+data['user']
 elif 'CIFSdom' in data['type']:
  cmdline=['/TopStor/encthis.sh',data["domname"],data["dompass"]]
  data["dompass"]=subprocess.run(cmdline,stdout=subprocess.PIPE).stdout.decode().split('_result')[1].replace('/','@@sep')

  datastr = data['pool']+' '+data['name']+' '+data['size']+' '+' '+data['ipaddress']+' '+data['Subnet']+' '+data['active']+' '+data['user']+' '+data['owner']+' '+data['user']+' '+ data["domname"]+' '+ data["domsrv"]+' '+ data["domip"]+' '+ data["domadmin"]+' '+ data["dompass"]
 else:
  datastr = data['pool']+' '+data['name']+' '+data['size']+' '+data['groups']+' '+data['ipaddress']+' '+data['Subnet']+' '+data['active']+' '+data['user']+' '+data['owner']+' '+data['user']
 print('#############################')
 print(data)
 print(datastr)
 print('###########################')
 cmndstring = '/TopStor/VolumeCreate'+data['type']+' '+leaderip+' '+datastr
 z= cmndstring.split(' ')
 msg={'req': 'Pumpthis', 'reply':z}
 sendhost(ownerip, str(msg),'recvreply',myhost)
 return data

def getlogin(token):
 global leaderip
 logindata = get('login',token)[0]
 if logindata == '_1':
  logmsg.sendlog('Lognno0','warning','system',token)
  return 'baduser'
 oldtimestamp = logindata[1].split('/')[1]
 user = logindata[0].split('/')[1]
 if int(oldtimestamp) < int(timestamp()):
  dels('login',token)
  loggedusers.pop(token, None)
  logmsg.sendlog('Lognsa0','warning','system',user)
  print('isssss######ss##########33','baduser')
  return 'baduser'
 userdict, token = setlogin(leaderip, myhost,user,'!',token) 
 if token == 0:
  logmsg.sendlog('Lognsa0','warning','system',user)
  return 'baduser'
  print('#################33','baduser')
   
  return 'baduser'
 loggedusers[token] = userdict.copy()
 print('iamokkkkkkkkkkkkkkkkkk')
 return user 

@app.route('/api/v1/logout', methods=['GET','POST'])
def logout():
 global leaderip
 data = request.args.to_dict()
 dels('login',data['token'])
 loggedusers.pop(data['token'], None)
 return data

@app.route('/api/v1/login/test', methods=['GET','POST'])
def testlogin():
 data = request.args.to_dict()
 loginresponse = getlogin(data['token'])
 return { 'response': loginresponse }

@app.route('/api/v1/login', methods=['GET','POST'])
def login():
 data = request.args.to_dict()
 print('#######################')
 print(data)
 print('#######################')
 userdict, token = setlogin(leaderip,myhost, data['user'],data['pass'])
 if token != 0:
  loggedusers[token] = userdict.copy()
  logmsg.sendlog('Lognsu0','info','system',data['user'])
  print('login okkkkkkk',loggedusers)
 else:
  print('login faileddddddddddddddddddd')
  logmsg.sendlog('Lognfa0','error','system',data['user'])
  token = 'baduser'
 return jsonify({'token':token})
@app.route('/api/v1/users/usersauth', methods=['GET','POST'])
@login_required
def usersauth(data):
 global allinfo
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 cmndstring = '/TopStor/Priv.py '+leader+' '+leaderip+' '+myhost+' '+myhostip+' '+data['tochange']+' '+data['auths'].replace(',','/')+' '+data['user']
 postchange(cmndstring)
 return data

@app.route('/api/v1/volumes/config', methods=['GET','POST'])
@login_required
def volumeconfig(data):
 global allinfo, myhost
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 getalltime()
 volume = allinfo['volumes'][data['volume']]
 owner = volume['host']
 if owner == leader:
  ownerip = leaderip
 else:
  ownerip = allinfo['hosts'][owner]['ipaddress']
 datastr = ''
 data['owner'] = allinfo['hosts'][allinfo['pools'][volume['pool']]['host']]['name']
 if 'ISCSI' in data['type']:
  data['chapuser']='MoatazNegm'
  data['chappas']='MezoAdmin'
  if 'ipaddress' not in data:
   data['ipaddress'] = volume['ipaddress']
  else:
    isvu =  int(is_valid_ip(data['ipaddress']))+int(is_unique_ip(data['ipaddress'],volume['prot']))
    if isvu == 0:
        print('ip is valid')
    else:
        if isvu < 100:
            logmsg.sendlog('IPaddrfa','error','system',loggedusers[data['token']]['user'])
        elif isvu > 10 and isvu < 120: 
            logmsg.sendlog('IPadduqfa','error','system',loggedusers[data['token']]['user'])
        else:
            logmsg.sendlog('IPnamuqfa','error','system',loggedusers[data['token']]['user'])
        return data

  if 'initiators' not in data:
   data['initiators'] = volume['initiators']
  if 'portalport' not in data:
   data['portalport'] = volume['portalport']
  for ele in data:
   volume[ele] = data[ele] 
  datastr = volume['pool']+' '+volume['name']+' '+str(volume['quota'])+' '+data['ipaddress']+' '+str(volume['Subnet'])+' '+data['portalport']+' '+data['initiators']+' '+data['chapuser']+' '+data['chappas']+' '+volume['statusmount']+' '+data['user']+' '+data['owner']+' '+data['user']
 else:

  if 'groups' in data and len(data['groups']) < 1: 
   data['groups'] = 'NoGroup'
  for ele in data:
   volume[ele] = data[ele] 
  datastr = volume['pool']+' '+volume['name']+' '+str(volume['quota'])+' '+volume['groups']+' '+volume['ipaddress']+' '+str(volume['Subnet'])+' '+volume['statusmount']+' '+volume['host']+' '+volume['user']
  print('33333333333333333333333333333333333333333333333#############################')
  print('volume',volume)
  print('owner',ownerip)
  print('33333333333333333333333333333333333333333333333#############################')
 cmndstring = '/TopStor/VolumeChange'+data['type']+' '+leaderip+' '+datastr
 z= cmndstring.split(' ')
 msg={'req': 'Pumpthis', 'reply':z}
 sendhost(ownerip, str(msg),'recvreply',myhost)
 #config(data)
 return data

@app.route('/api/v1/user/changepass', methods=['GET','POST'])
@login_required
def changepass(data):
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 data['user'] = data['response']
 print('#############################')
 print(data)
 print('###########################')
 config(leader, leaderip,myhost, data)
 return data



@app.route('/api/v1/hosts/config', methods=['GET','POST'])
@login_required
def hostconfig(data):
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 if 'ipaddr' in data:
    isvu =  int(is_valid_ip(data['ipaddr']))+int(is_unique_ip(data['ipaddr']))
    if isvu == 0:
        print('ip is valid')
    else:
        if isvu < 100:
            logmsg.sendlog('IPaddrfa','error','system',loggedusers[data['token']]['user'])
        elif isvu > 10 and isvu < 120: 
            logmsg.sendlog('IPadduqfa','error','system',loggedusers[data['token']]['user'])
        else:
            logmsg.sendlog('IPnamuqfa','error','system',loggedusers[data['token']]['user'])
        return data
 if 'cluster' in data:
    dataip = data['cluster'].split('/')[0]   
    isvu =  int(is_valid_ip(dataip))+int(is_unique_ip(dataip))
    if 'ipaddr' in data:
        if dataip == data['ipaddr']:
            isvu = 1
    if isvu == 0:
        print('ip is valid')
    else:
        if isvu == 1:
            logmsg.sendlog('IPaddrclufa','error','system',loggedusers[data['token']]['user'])
        elif isvu < 100:
            logmsg.sendlog('IPaddrfa','error','system',loggedusers[data['token']]['user'])
        elif isvu > 10 and isvu < 120: 
            logmsg.sendlog('IPadduqfa','error','system',loggedusers[data['token']]['user'])
        else:
            logmsg.sendlog('IPnamuqfa','error','system',loggedusers[data['token']]['user'])
        return data

 datastr = ''
 for ele in data:
  datastr += ele+'='+data[ele]+' '
 datastr = datastr[:-1]
 print('#############################')
 print(data)
 print('###########################')
 config(leader, leaderip, myhost, data)
 return data

@app.route('/api/v1/hosts/joincluster', methods=['GET','POST'])
@login_required
def hostjoincluster(data):
 global leaderip, myhost
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 data['user'] = data['response']
 discover()
 data['leaderip'] = leaderip
 data ['myhost'] = myhost
 Joincluster.do(data) 
 cmndstring = '/TopStor/promserver.sh '+leaderip+' from fapi'
 postchange(cmndstring)
 return data


@app.route('/api/v1/hosts/evacuate', methods=['GET','POST'])
@login_required
def hostevacuate(data):
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 data['user'] = data['response']
 #with open('/root/Evacuate','w') as f:
  #f.write(" ".join([leaderip, myhost, data['name'], data['user']]))
 discover()
 Evacuate.do(leaderip, myhost, data['name'], data['user']) 
 return data

@app.route('/api/v1/volumes/snapshots/snaprollback', methods=['GET','POST'])
@login_required
def volumesnapshotrol(data):
 global allinfo, myhost
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 getalltime()
 volume = allinfo['snapshots'][data['name']]['volume']
 pool = allinfo['snapshots'][data['name']]['pool']
 owner = allinfo['snapshots'][data['name']]['host']
 ownerip = allinfo['hosts'][owner]['ipaddress']
 cmndstring = "/TopStor/SnapShotRollback "+pool+" "+volume+" "+data['name']+" "+data['user']
 z= cmndstring.split(' ')
 msg={'req': 'Pumpthis', 'reply':z}
 print('##################################')
 print(data)
 print('################################333')
 sendhost(ownerip, str(msg),'recvreply',myhost)
        		 
 return data


@app.route('/api/v1/volumes/snapshots/perioddelete', methods=['GET','POST'])
@login_required
def volumesnapshotperioddel(data):
 global allinfo, myhost
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 getalltime()
 owner = allinfo['snapperiods'][data['name']]['host']
 ownerip = allinfo['hosts'][owner]['ipaddress']
 cmndstring = "/TopStor/SnapShotPeriodDelete "+leaderip+" "+data['name']+" "+data['user']
 z= cmndstring.split(' ')
 msg={'req': 'Pumpthis', 'reply':z}
 sendhost(ownerip, str(msg),'recvreply',myhost)
 return data  


@app.route('/api/v1/volumes/snapshots/snapshotdel', methods=['GET','POST'])
@login_required
def volumesnapshotdel(data):
 global allinfo, myhost 
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 getalltime()
 volume = allinfo['snapshots'][data['name']]['volume']
 pool = allinfo['snapshots'][data['name']]['pool']
 owner = allinfo['snapshots'][data['name']]['host']
 ownerip = allinfo['hosts'][owner]['ipaddress']
 cmndstring = "/TopStor/SnapShotDelete "+pool+" "+volume+" "+data['name']+" "+data['user']
 z= cmndstring.split(' ')
 msg={'req': 'Pumpthis', 'reply':z}
 print('##################################')
 print(data)
 print('################################333')
 sendhost(ownerip, str(msg),'recvreply',myhost)
        		 
 return data

@app.route('/api/v1/volumes/volumeactive', methods=['GET','POST'])
@login_required
def volumeactive(data):
 global allinfo, myhost
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 pool = allinfo['volumes'][data['name']]['pool']
 prot = allinfo['volumes'][data['name']]['prot']
 owner = allinfo['volumes'][data['name']]['host']
 ownerip = allinfo['hosts'][owner]['ipaddress']
 cmndstring = "/TopStor/Volumeactive.py "+leaderip+" "+myhost+" "+pool+" "+data['name']+" "+prot+" "+data['active']+" "+data['user']
 print('##################################')
 print('volumeactive',cmndstring)
 print('##################################')
 z= cmndstring.split(' ')
 msg={'req': 'Pumpthis', 'reply':z}
 sendhost(ownerip, str(msg),'recvreply',myhost)
 return data



@app.route('/api/v1/volumes/volumedel', methods=['GET','POST'])
@login_required
def volumedel(data):
 global allinfo, myhost
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 getalltime()
 pool = allinfo['volumes'][data['name']]['pool']
 owner = allinfo['volumes'][data['name']]['host']
 ownerip = allinfo['hosts'][owner]['ipaddress']
 cmndstring = "/TopStor/VolumeDelete"+data['type']+" "+leaderip+" "+pool+" "+data['name']+" "+data['type']+" "+data['user']
 z= cmndstring.split(' ')
 msg={'req': 'Pumpthis', 'reply':z}
 print('##################################')
 print(data)
 print('################################333')
 sendhost(ownerip, str(msg),'recvreply',myhost)
        		 
 return data

@app.route('/api/v1/groups/groupdel', methods=['GET','POST'])
@login_required
def groupdel(data):
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 cmndstring = '/TopStor/UnixDelGroup '+leaderip+' '+data.get('name')+' '+data['user'] 
 postchange(cmndstring)
 return data

@app.route('/api/v1/partners/partnerdel', methods=['GET','POST'])
@login_required
def partnerdel(data):
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 cmndstring = '/TopStor/PartnerDel.py '+data.get('name')+' no '+data['user']
 postchange(cmndstring)
 return data



@app.route('/api/v1/users/userdel', methods=['GET','POST'])
@login_required
def userdel(data):
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 cmndstring = '/TopStor/UnixDelUser '+leaderip+' '+data.get('name')+' '+data['user']
 postchange(cmndstring)
 return data

@app.route('/api/v1/groups/UnixAddgroup', methods=['GET','POST'])
@login_required
def UnixAddGroup(data):
 global allusers, allgroups
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 usrstr = ''
 usrs = data['users']
 if len(usrs) < 1:
  usrstr = 'NoUser'
 else:
  for usr in usrs.split(','):
   for suser in allusers:
    if str(suser['id']) == str(usr):
     usrstr += suser['name']+',' 
  usrstr = usrstr[:-1]

 if int(is_unique_name(data['name']))==1000:
    logmsg.sendlog('IPnamuqfa','error','system',loggedusers[data['token']]['user'])
    return data
 cmndstring = '/TopStor/UnixAddGroup '+leaderip+' '+data['name']+' '+' users'+usrstr+' '+data['user']
 postchange(cmndstring)
 return data

@app.route('/api/v1/partners/AddPartner', methods=['GET','POST'])
@login_required
def AddPartner(data):
 if 'baduser' in data['response']:
  return {'response': 'baduser'} 
 isvu =  int(is_valid_ip(data['ip']))+int(is_unique_ip(data['ip']))
 if isvu == 0:
        print('ip is valid')
 else:
        if isvu < 100:
            logmsg.sendlog('IPaddrfa','error','system',loggedusers[data['token']]['user'])
        elif isvu > 10 and isvu < 120: 
            logmsg.sendlog('IPadduqfa','error','system',loggedusers[data['token']]['user'])
        else:
            logmsg.sendlog('IPnamuqfa','error','system',loggedusers[data['token']]['user'])
        return data

 print('##########################33333')
 print(data)
 print('##########################33333')
 cmdstring = '/TopStor/PartnerAdd.py '+data['ip']+' '+data['alias']+' '+data['type']+' '+data['port']+' '+data['pass']+' '+data['user'] + ' init'
 postchange(cmdstring)
 return data

@app.route('/api/v1/users/UnixAddUser', methods=['GET','POST'])
@login_required
def UnixAddUser(data):
 global allgroups, leaderip
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 pool = data['Volpool']
 if 'NoHome' in data['Volpool'] or '-' in data['Volpool']:
  pool = 'NoHome'
 else:
    isvu =  int(is_valid_ip(data['HomeAddress']))+int(is_unique_ip(data['HomeAddress'],'HOME'))
    if isvu == 0:
        print('ip is valid')
    else:
        if isvu < 100:
            logmsg.sendlog('IPaddrfa','error','system',loggedusers[data['token']]['user'])
        elif isvu > 10 and isvu < 120: 
            logmsg.sendlog('IPadduqfa','error','system',loggedusers[data['token']]['user'])
        else:
            logmsg.sendlog('IPnamuqfa','error','system',loggedusers[data['token']]['user'])
        return data


 if int(is_unique_name(data['name']))==1000:
    logmsg.sendlog('IPnamuqfa','error','system',loggedusers[data['token']]['user'])
    return data
    
 grps = data.get('groups')
 groupstr = ''
 allgroups = getgroups()
 if len(grps) < 1:
  groupstr = 'NoGroup'
 else:
  for grp in grps.split(','):
   groupstr += allgroups[int(grp)][0]+','
  groupstr = groupstr[:-1]
 cmndstring = '/TopStor/UnixAddUser '+leaderip+' '+data.get('name')+' '+pool+' groups'+groupstr+' ' \
     +data.get('Password')+' '+data.get('Volsize')+'G '+data.get('HomeAddress')+' '+data.get('HomeSubnet')+' hoststub'+' '+data['user']

 postchange(cmndstring)
 return data 

@app.route('/api/v1/volumes/grouplist', methods=['GET'])
@login_required
def api_volumes_groupslist(data):
 global allgroups, allusers
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 thegroup = [] 
 api_users_userslist(data)
 for group in allgroups:
  groupusers = []
  for user in allusers:
   if user['name'] in str(group[2]):
    groupusers.append(user['id'])
  if len(groupusers) < 1:
   groupusers=["NoUser"]
  thegroup.append({'text':group[0], 'id':group[1], 'users':groupusers})
 return jsonify({'results':thegroup})




@app.route('/api/v1/groups/grouplist', methods=['GET'])
@login_required
def api_groups_groupslist(data):
 global allgroups, allusers
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 thegroup = [] 
 api_users_userslist(data)
 for group in allgroups:
 # if group[0] == 'Everyone':
 #  continue

  groupusers = []
  for user in allusers:
   grpusrs = str(group[2]).split(',')
   for grp  in grpusrs:
    if user['name'] == grp:
     groupusers.append(user['id'])
#   if user['name'] in str(group[2]) :
#    groupusers.append(user['id'])
  if len(groupusers) < 1:
   groupusers=["NoUser"]
  thegroup.append({'name':group[0], 'id':group[1], 'users':groupusers})
 return jsonify({'allgroups':thegroup})

@app.route('/api/v1/users/userauths', methods=['GET'])
@login_required
def userauths(data):
 global allgroups, allusers, leaderip
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 if  data['username'] == 'admin':
  return {'auths':'true','response':data['response']}
 userlst = etcdgetjson(leaderip,'usersinfo','--prefix')
 for user in userlst:
  username = user['name'].replace('usersinfo/','')
  if username == data['username']:
   priv = '/'.join(user['prop'].split('/')[4:])
   break
 return jsonify({'auths':priv, 'response':data['response']})

@app.route('/api/v1/partners/partnerlist', methods=['GET'])
@login_required
def api_partners_userslist(data):
 global leaderip
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 allpartners=[]
 partnerlst = etcdgetjson(leaderip,'Partner/','--prefix')
 for partner in partnerlst:
  alias =  partner["name"].split('/')[1] 
  split = partner["prop"].split('/') 
  allpartners.append({'alias': alias, "ip":split[0], "type":split[1], "port":split[2]})
 return { "allpartners":allpartners }

@app.route('/api/v1/users/userlist', methods=['GET'])
@login_required
def api_users_userslist(data):
 global allgroups, allusers, leaderip
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 userlst = etcdgetjson(leaderip,'usersinfo','--prefix')
 allgroups = getgroups()
 userdict = dict()
 allusers = []
 for group in allgroups:
  groupid = group[1]
  grpusers = group[2].split(',')
  for grpuser in grpusers:
   if grpuser not in userdict:
    userdict[grpuser] = []
   userdict[grpuser].append(str(groupid))
 usersnohome = []
 nohomeid = 0
 uid = 0
 for user in userlst:
  username = user['name'].replace('usersinfo/','')
  usersize = user['prop'].split('/')[3]
  userpool = user['prop'].split('/')[1]
  priv = '/'.join(user['prop'].split('/')[4:])
  if username not in userdict:
   groups = ['NoGroup']
  else:
   groups = userdict[username]
  allusers.append({"name":username, 'id':uid, "pool":userpool, "size":usersize, "groups":groups, 'priv':priv})
  uid += 1
  if 'NoHome' in userpool:
   usersnohome.append({ 'id':nohomeid, 'text': username })
   nohomeid += 1 
 alldict = dict()
 alldict['allusers'] = allusers
 alldict['allgroups'] = allgroups
 alldict['usersnohome'] = usersnohome
 return jsonify(alldict)

@app.route('/api/v1/groups/userlist', methods=['GET'])
@login_required
def api_groups_userlist(data):
 global allusers
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 usr = []
 api_users_userslist(data)
 for user in allusers:
  usr.append({'id':user['id'],'text':user['name']})
 return jsonify({'results':usr})


@app.route('/api/v1/users/grouplist', methods=['GET'])
@login_required
def api_users_grouplist(data):
 global allgroups
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 allgroups = getgroups()
 grp = []
 for group in allgroups:
  grp.append({'id':group[1],'text':group[0]})
 return jsonify({'results':grp})


@app.route('/api/v1/pools/actionOnDisk', methods=['GET','POST'])
@login_required
def offlineOrOnlineDisk(data):
    global allinfo, myhost, leaderip
    if 'baduser' in data['response']:
      return {'response': 'baduser'}
    getalltime()
    action = data['action']
    pool = data['pool']
    disk = data['actualdisk'] # "scsi-*" format. 
    #disk = data['actualdisk'] # "sd*" format.
    owner = allinfo['pools'][pool]['host']
    ownerip = allinfo['hosts'][owner]['ipaddress']
    datastr = myhost + ' ' + data['user'] + ' ' + leaderip + ' ' + action + ' ' + pool + ' ' + disk
    cmdline = 'python /TopStor/actionOnDisk.py ' + datastr
    z = cmdline.split(' ')
    msg = {'req': 'Pumpthis', 'reply':z}
    sendhost(ownerip, str(msg),'recvreply',myhost)
    return data

@app.route('/api/v1/hosts/getConfig', methods=['GET','POST'])
@login_required
def getNodeConfigFile(data):
    global leaderip
    if 'baduser' in data['response']:
      return {'response': 'baduser'}
    nodeName = data["nodeName"]
    nodeConfig = getConfig(leaderip, nodeName)
    file_path = "/TopStordata/" + nodeName + "_config.txt"
    return send_file(file_path, mimetype='text/plain', as_attachment=True)

@app.route('/api/v1/hosts/getAllConfig', methods=['GET','POST'])
@login_required
def getAllConfigFiles(data):
    global leaderip, readyhosts
    if 'baduser' in data['response']:
      return {'response': 'baduser'}
    hostsready()
    configFiles = []
    zipfilePath = "/TopStordata/All_Configs.zip"
    getConfig(leaderip, myhost)
    downloadConfig(leaderip, myhost)
    for host in readyhosts:
        nodeName = host["name"]
        nodeip = host['ip']
        filePath = "/TopStordata/config_" + nodeName + ".txt"
        configFiles.append((filePath, 'config_'+nodeName + ".txt"))
    with zipfile.ZipFile(zipfilePath, "w") as zipF:
        for file in configFiles:
            zipF.write(file[0], file[1] ,compress_type = zipfile.ZIP_DEFLATED)
    return send_file(zipfilePath, as_attachment=True)

leaderip =0 
myhost=0
if __name__=='__main__':
    #leader = sys.argv[2]
    #leaderip = sys.argv[1]
    leaderip = get('leaderip')[0]
    myhost = get('clusternode')[0]
    myhostip = get('clusternodeip')[0]
    leader = get('leader')[0]
    logmsg.initlog(leaderip,myhost)
    #myhost = sys.argv[2]
    getalltime()
   #myhostip = sys.argv[5]
    app.run(host="0.0.0.0", port=5001)
