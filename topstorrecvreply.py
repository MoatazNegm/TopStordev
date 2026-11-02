#!/usr/bin/python3
import pika, sys, subprocess, threading, queue
import actionreply
from secretmask import bus_log_text, bus_scrub_once


# QSD5.317: the callback used to run the request inside pika's consume loop.  A request that takes minutes (UnixAddUser of a
# user with a home folder: the share container start sets every user's samba password) kept the loop from answering the
# broker's heartbeat; RabbitMQ closed the connection, the process died, the looper restarted it and every request that was
# already delivered (auto ack) behind the long one was lost -- users, groups and password changes were "accepted" and
# never executed.  Now the loop only hands the body to one worker thread (requests still run one after the other, in order).
work = queue.Queue()

def worker():
 while True:
    body = work.get()
    try:
        # QSD5.347: the body as written down has its secrets masked (bus_log_text: the sender's masked copy, then the
        # fixed list of secret arguments); it used to be the clear body, the UnixAddUser password included (QX-221 step 4).
        # One line per message (the old file was one endless line).
        # A failing debug write never stops the request.
        try:
            shown = 'b"' + bus_log_text(body) + '"'
            with open("/root/recvreply",'a') as f:
                f.write(" ".join([leader, leaderip, myhost, myip,etcdip, shown])+'\n')
            print(" ".join([leader, leaderip, myhost, myip,etcdip, shown]))
        except Exception as e:
            print('recvreply log failed:', e)
        actionreply.do(leader, leaderip, myhost, myip,etcdip, body.decode())
    except Exception as e:
        print('recvreply request failed:', e)
        sys.stdout.flush()

def callback(ch, method, properties, body):
    work.put(body)

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
bus_scrub_once()      # QSD5.347: once per node, the bus logs of older versions (clear passwords) are emptied
try:
    import shadowscrub
    # QSD5.347: /etc/shadow fields of older TopStor users (clear password) -> '!'.  QSD5.348: on every start (cheap when
    # clean), /etc/shadow- and /opt/passwds/shadow cleaned too.  QSD5.349: every managed user's open field, admin's
    # included, -> '!' (no hashing); /root/plhashtmp removed
    shadowscrub.scrub_check()
except Exception as e:
    print('shadowscrub failed:', e)
threading.Thread(target=worker, daemon=True).start()
cred = pika.PlainCredentials('rabb_Mezo', 'YousefNadody')
param = pika.ConnectionParameters(myip,5672, '/', cred)
conn = pika.BlockingConnection(param)
chann= conn.channel()
chann.queue_declare(queue='recvreply')
#chann.basic_consume(callback, queue='recvreply', no_ack=True)
chann.basic_consume('recvreply',callback, True)
chann.start_consuming()
