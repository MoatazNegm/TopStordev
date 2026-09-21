#!/usr/bin/python3
import sys
sys.path.insert(0, '/TopStor')
from etcdgetpy import etcdget as get
from Hostconfig import config

leaderip = '10.11.11.249'
leader = get(leaderip, 'leader')[0]
myhost = leader

print('leader:', leader, 'leaderip:', leaderip, 'myhost:', myhost)

arglist = {
    'ipaddr': '10.11.11.25',
    'ipaddrsubnet': '24',
    'id': '0',
    'user': 'admin',
    'name': 'dhcp290917',
    'discovered': True
}

result = config(leader, leaderip, myhost, arglist)
print('config() result:', result)
