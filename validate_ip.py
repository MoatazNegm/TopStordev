#!/usr/bin/python3
# Read-only check: reimplements fapi.py's is_valid_ip/is_unique_ip logic
# exactly, without importing fapi.py (which would start a Flask server).
import sys, re, ipaddress
sys.path.insert(0, '/TopStor')
from etcdgetlocalpy import etcdget as get

leaderip = '10.11.11.249'

def is_valid_ip(ip):
    try:
        ipaddress.ip_address(ip)
        return 0
    except ValueError:
        return 10

def is_unique_ip(ip, vtype='NZ#@A'):
    if not ip or not str(ip).strip():
        return 0
    allvols = get('vol', '--prefix')
    allvols = [x for x in allvols if vtype not in str(x)]
    allvols = str(allvols)
    allnodes = get('Active', '--prefix')
    allnodes = str(allnodes)
    allpartners = get('Partner', '--prefix')
    allpartners = str(allpartners)
    allips = allvols + '/' + leaderip + '/' + allnodes + '/' + allpartners
    ip_pattern = rf'\b{re.escape(ip)}\b'
    if bool(re.search(ip_pattern, allips)):
        print("Invalid IP - collision found")
        print("allips was:", allips)
        return 100
    print("Valid IP - no collision")
    return 0

for testip in ['10.11.11.27', '10.11.11.25', '10.11.11.30']:
    v = is_valid_ip(testip)
    u = is_unique_ip(testip)
    print(f'{testip}: is_valid_ip={v} is_unique_ip={u} isvu={v+u}')
