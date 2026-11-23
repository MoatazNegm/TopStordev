#!/usr/bin/python3
import pika, sys, subprocess, threading, traceback
import actionreply
from secretmask import bus_log_text, bus_scrub_once

# The command consumer of this node (queue 'recvreply'). Commands run one at a time, in queue order (a user add and a later
# delete of the same user must keep their order).
# Test 619 step 1: it consumed with auto_ack and ran each command INSIDE the pika callback, so while a command ran (a home
# job on the pool owner takes 2-3 min) pika serviced no heartbeat; the broker closed the connection ("missed heartbeats from
# client") and every command it had already pushed to this client (acked on delivery, not run yet) was lost.
# Now a command is taken from the queue (basic_get) only when the previous one has finished, it runs in a worker thread, and
# the main thread keeps servicing the connection (heartbeats) meanwhile. The commands not started yet stay in the broker's
# queue, so a dropped connection loses none of them; the looper (receivereplylooper.sh) restarts this script and it goes on.
leader, leaderip, myhost, myip, etcdip = '', '', '', '', ''

def record(body):
 global leader, leaderip, myhost, myip, etcdip
 # merge M+A: A's record() with M's masking (QSD5.347, QX-221 step 4: bus_log_text = the sender's masked copy, then the
 # fixed list of secret arguments; the clear body held the UnixAddUser password).  One line per message; a failing debug
 # write never stops the request.
 try:
  shown = 'b"' + bus_log_text(body) + '"'
  print(" ".join([leader, leaderip, myhost, myip,etcdip, shown]))
  with open("/root/recvreply",'a') as f:
     f.write(" ".join([leader, leaderip, myhost, myip,etcdip, shown])+'\n')
 except Exception as e:
  print('recvreply log failed:', e)

def runjob(body):
 global leader, leaderip, myhost, myip, etcdip
 try:
  actionreply.do(leader, leaderip, myhost, myip,etcdip, body.decode())
 except Exception:
  # one bad command must not stop the consumer (it used to end the script, and the commands prefetched with it were lost)
  traceback.print_exc()

def consume(conn, chann, queue='recvreply', idle=0.25):
 worker = None
 while True:
  if worker is None or not worker.is_alive():
   method, properties, body = chann.basic_get(queue, auto_ack=True)
   if method is not None:
    record(body)
    # not a daemon: if the connection fails while it runs, the script still waits for the command to finish before it
    # exits, so the restarted consumer never runs the next command beside it
    worker = threading.Thread(target=runjob, args=(body,))
    worker.start()
    continue
  # heartbeats and other connection traffic, while a command runs or while the queue is empty
  conn.process_data_events(time_limit=idle)

if __name__ == '__main__':
 cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py leader'
 leader=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
 cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py leaderip'
 leaderip=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
 cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py clusternode'
 myhost=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
 cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py clusternodeip'
 myip=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
 if leader == myhost:
     etcdip = leaderip
 else:
     etcdip = myip
 print('myip',myip)
 bus_scrub_once()      # QSD5.347 (M): once per node, the bus logs of older versions (clear passwords) are emptied
 try:
     import shadowscrub
     # QSD5.347-349 (M): /etc/shadow open fields of managed users -> '!', on every start (cheap when clean)
     shadowscrub.scrub_check()
 except Exception as e:
     print('shadowscrub failed:', e)
 cred = pika.PlainCredentials('rabb_Mezo', 'YousefNadody')
 param = pika.ConnectionParameters(myip,5672, '/', cred)
 conn = pika.BlockingConnection(param)
 chann= conn.channel()
 chann.queue_declare(queue='recvreply')
 #chann.basic_consume('recvreply',callback, True)   (auto_ack, run inside the callback: see above)
 consume(conn, chann)
