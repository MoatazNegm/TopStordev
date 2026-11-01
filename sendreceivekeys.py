#!/usr/bin/python3
import sys
from sendhost import sendhost
from secretmask import MASK

ownerip = sys.argv[1]
myhost = sys.argv[2]
myhostip = sys.argv[3]
nodeip = sys.argv[4]
repliport = sys.argv[5]
phrase = sys.argv[6]
result = sys.argv[7]
z=['/TopStor/receivekeys.sh',myhost,myhostip,nodeip, repliport, phrase, result]
# QSD5.344: the pass phrase (z[5]) is masked in the debug copy and in /root/sendhostparam
zlog = z[:5]+[MASK]+z[6:]
with open('/root/sendrectmp','w') as f:
    f.write(' '.join(zlog)+'\n')
    f.write(ownerip)
msg={'req': 'Exchange', 'reply':z}
sendhost(ownerip, str(msg),'recvreply',myhost, logreq=str({'req': 'Exchange', 'reply':zlog}))
