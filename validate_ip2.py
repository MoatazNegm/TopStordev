#!/usr/bin/python3
import sys, re
sys.path.insert(0, '/TopStor')
from etcdgetlocalpy import etcdget as get

leaderip = '10.11.11.249'

def is_unique_ip(ip, vtype='NZ#@A'):
    allvols = get('vol', '--prefix')
    allvols = [x for x in allvols if vtype not in str(x)]
    allvols = str(allvols)
    allnodes = get('Active', '--prefix')
    allnodes = str(allnodes)
    allpartners = get('Partner', '--prefix')
    allpartners = str(allpartners)
    allips = allvols + '/' + leaderip + '/' + allnodes + '/' + allpartners
    print('DEBUG allips:', allips[:500])
    ip_pattern = rf'\b{re.escape(ip)}\b'
    if bool(re.search(ip_pattern, allips)):
        return 100
    return 0

for testip in ['10.11.11.19', '10.11.11.18', '10.11.11.20']:
    print(testip, 'is_unique_ip=', is_unique_ip(testip))
