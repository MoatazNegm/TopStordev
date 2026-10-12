#!/usr/bin/python3
import pika, sys, subprocess, threading, queue
import actionreply


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
        with open("/root/recvreply",'a') as f:
            f.write(" ".join([leader, leaderip, myhost, myip,etcdip, str(body)]))
        print(" ".join([leader, leaderip, myhost, myip,etcdip, str(body)]))
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
threading.Thread(target=worker, daemon=True).start()
cred = pika.PlainCredentials('rabb_Mezo', 'YousefNadody')
param = pika.ConnectionParameters(myip,5672, '/', cred)
conn = pika.BlockingConnection(param)
chann= conn.channel()
chann.queue_declare(queue='recvreply')
#chann.basic_consume(callback, queue='recvreply', no_ack=True)
chann.basic_consume('recvreply',callback, True)
chann.start_consuming()
