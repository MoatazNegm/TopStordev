#!/usr/bin/python3
import pika
from ast import literal_eval as mtuple

def sendhost(host, req, que, frmhst, port=5672, logreq=None):
 # QSD5.344: logreq = the text written to the debug file instead of req (fapi passes the request with its secrets masked)
 with open('/root/sendhostparam','a') as f:
  f.write(host+' '+str(req if logreq is None else logreq)+' '+str(que)+' '+str(frmhst)+'\n')
# Check if the file needs to be pruned
 with open('/root/sendhostparam', 'r') as f:
        lines = f.readlines()

 if len(lines) > 30:
        # Keep only the last 30 lines
        with open('/root/sendhostparam', 'w') as f:
            f.writelines(lines[-30:])
# creds=pika.PlainCredentials('rabb_'+frmhst,'YousefNadody')
 creds=pika.PlainCredentials('rabb_Mezo','YousefNadody')
 param=pika.ConnectionParameters(host, port, '/', creds)
 conn=pika.BlockingConnection(param)
 chann=conn.channel()
 body = str(req)
 if logreq is not None:
  # QSD5.347: the masked copy of the command rides along as 'logreply', so the receiving node writes it to its bus logs
  # (/root/recvreply, /root/recv ...) instead of the clear one (UnixAddUser password, QX-221 step 4); executors read 'reply'
  try:
   from secretmask import with_logreply
   body = with_logreply(body, logreq)
  except Exception:
   body = str(req)
 chann.basic_publish(exchange='',routing_key=que, body=body)
 conn.close()
if __name__ == "__main__":
 import sys
 if len(sys.argv) < 2:
    import os
    host='10.11.11.250' if (os.path.exists('/.dockerenv') or os.path.isdir('/sys/class/net/eth10')) else '10.11.11.100'
    req = {'req': 'Pumpthis', 'reply': ['/TopStor/VolumeCreateCIFS', '10.11.11.100', 'pdhcp1055322164', 'nf5', '1G', 'Everyone', '10.11.11.34', '24', 'active', 'admin', 'dhcp152953', 'admin']}
    que='recvreply'
    frmhst='dhcp152953'
    sendhost(host, req, que, frmhst)
 else:
    sendhost(*sys.argv[1:])
 
