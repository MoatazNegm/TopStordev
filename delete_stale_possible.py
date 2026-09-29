import sys
sys.path.insert(0, '/TopStor')
from etcddel import etcddel as dels
from etcdgetlocalpy import etcdget as get

leaderip = '10.11.11.249'
name = 'dhcp278102'

print("--- before ---")
print("possible:", get('possible', '--prefix'))
print("ready:", get('ready', '--prefix'))

dels(leaderip, 'possible', name)

print("--- after ---")
possible = get('possible', '--prefix')
ready = get('ready', '--prefix')
print("possible:", possible)
print("ready:", ready)

r = len(ready) if ready else 0
p = len(possible) if possible else 0
print("ready count:", r, "possible count:", p, "ready-possible:", r - p, ">=2?", (r - p) >= 2)
