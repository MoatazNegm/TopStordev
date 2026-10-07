#!/usr/bin/python3
import subprocess, sys
from time import time
from etcdput import etcdput as put 
from etcddel import etcddel as dels

def ioperf(myclusterip,myhost):

 #cmdline="/TopStor/loadavg.sh"
 #cores, load =subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').split(' ')
 #print( 'cores',str(100*float(load)/float(cores)))
 cmdline='iostat -k'
 result=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').split('\n')
 #cpures = result[:4][-1].split()[:-1]
 #tcpu = 0
 #tcpu = round(float(cpures[0])+float(cpures[2]),2)
 #tcpu = 100*float(cores)/float(load)
 #tcpu = str(100*float(load)/float(cores))
 #print(float(cores), tcpu)
 #cmdline='docker exec etcdclient /TopStor/etcdput.py '+myclusterip+' cpuperf/'+myhost+' '+str(tcpu)
 #put(myclusterip,'cpuperf/'+myhost,str(tcpu))
 #result=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8')
 diskres = result[6:]
 diskresdict = {}
 for dsk in diskres:
  dsklst = dsk.split()
  if len(dsklst) < 1 :
   continue
  readpercent = (100*float(dsklst[4]))/(float(dsklst[4])+float(dsklst[5]))
  diskresdict[dsk.split()[0]] = {'tps': dsk.split()[1], 'throuput': round((float(dsk.split()[2])+float(dsk.split()[3]))/2,2), 'read': round(readpercent,2) }
 cmdline='lsscsi'
 result=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').split('\n')
 result = [(x.split()[3],x.split()[5].replace('/dev/','')) for x in result if 'LIO' in x ]
 disks = {}
 for res in result:
  if res[1] in diskresdict:
   disks[res[1]] = diskresdict[res[1]].copy()
   disks[res[1]]['name'] = res[0]
 cmdline='docker exec etcdclient /TopStor/etcddel.py '+myclusterip+' dskperf '+myhost
 result=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').split('\n')
 #dels(myclusterip,'dskperf',myhost)
 for dsk in disks:
  thedsk = disks[dsk]
  #cmdline='docker exec etcdclient /TopStor/etcdput.py '+myclusterip+' dskperf/'+myhost+'/'+thedsk['name']+' '+str(thedsk['tps'])+'/'+str(thedsk['through'])+'/'+str(thedsk['read'])+'/'+dsk
  put(myclusterip,'dskperf/'+myhost+'/'+thedsk['name'], str(thedsk['tps'])+'/'+str(thedsk['throuput'])+'/'+str(thedsk['read'])+'/'+dsk)
  #result=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8')
  # the file is not there on every node; without it this raised, and zpooltoimport.py -- which calls ioperf
  # right before 'zpool import' -- never imported a pool
  try:
   with open('/pacedata/perfmon') as f:
    perfmon = f.readline()
  except OSError:
   perfmon = '0'
  #if '1' in perfmon:
 # with open('/TopStordata/dskperfmon.txt','a') as f:
 #  f.write(str(time())+' dskperf/'+myhost+'/'+thedsk['name']+'\t '+str(thedsk['tps'])+'/'+str(thedsk['throuput'])+'/'+str(thedsk['read'])+'/'+dsk+'\n')
 #with open('/TopStordata/cpuperfmon.txt','a') as f:
 #  f.write(str(time())+' cpuperf/'+myhost+'\t'+str(tcpu)+'\n')

if __name__=='__main__':
 ioperf(*sys.argv[1:])
