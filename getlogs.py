#!/usr/bin/python3
from logqueue import queuethis
import subprocess
from time import time
import sys

with open('/TopStor/msgsglobal.txt') as f:
 logcatalog = f.read().split('\n')
logdict = dict()
for log in logcatalog:
 msgcode= log.split(':')[0]
 logdict[msgcode] = log.replace(msgcode+':','').split(' ')

def onedaylog():
 severity = ('info','warning','error')
 unsuclogon = 'Lognfa0'
 onedaylogdic = {'failedlogon': []} 
 for sev in severity:
  onedaylogdic[sev] = []
  nowis = int(time())
  nowfixed = str(nowis)[:4]
  cmdline='/TopStor/grepthis.sh '+nowfixed+' '+sev+' /TopStordata/TopStorglobal.log'
  result=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').split('\n')
  for res in result:
   if len(res.split()) < 4:
    continue
   if int(res.split()[-1]) > (nowis-(60*60*24*7)):
    onedaylogdic[sev].append(res)
    if 'Lognfa0' in res:
     onedaylogdic['failedlogon'].append(res)
 return onedaylogdic

def notifthis(notifbody,loc=3):
 msg = logdict[notifbody[loc]]
 msgbody = '.'
 notifc = 6
 for word in msg[4:]:
  if word == r'\:':
   # an escaped colon in msgsglobal.txt is a literal ':' in the text, not a placeholder (e.g. Priv1004)
   msgbody = msgbody[:-1]+' :.'
  elif word == ':':
   if len(notifbody) <= notifc:
    notifbody.append('<<fix>>')
   msgbody = msgbody[:-1]+' '+notifbody[notifc]+'.'
   notifc += 1
  elif len(word) > 0:
   msgbody = msgbody[:-1]+' '+word+'.' 
 notif = { 'importance':msg[0].replace(':',''), 'msgcode': notifbody[3], 'date':notifbody[0], 'time':notifbody[1],
	 'host':notifbody[2], 'type':notifbody[4], 'user': notifbody[5], 'msgbody': msgbody[1:]} 
 return notif


def getlogs(lines=100, *args):
 notiflist = []
 cmd = 'tail -n '+str(lines)+' /TopStordata/TopStorglobal.log'
 result=subprocess.run(cmd.split(' '),stdout=subprocess.PIPE)
 result = str(result.stdout.decode('utf8')).split('\n')
 for line in result:
   notifbody = line.replace('@@@',' ').replace('@@','').replace('@',' ').split(' ')
   if len(notifbody) < 6:
    continue
   notifbody[3],notifbody[4],notifbody[5] = notifbody[5],notifbody[3],notifbody[4]
   try:
    notiflist.append(notifthis(notifbody=notifbody))
   except KeyError:
    # a line whose code is not in msgsglobal.txt (e.g. the LogError lines of logmsg2.sh) must not fail info/logs
    continue
 return notiflist  

 
if __name__=='__main__':
 onedaylog()
 #getlogs(*sys.argv[1:])
