import sys
sys.path.insert(0, '/TopStor')
from etcdgetlocalpy import etcdget as get

ready = get('ready', '--prefix')
possible = get('possible', '--prefix')
active = get('ActivePartners', '--prefix')

print("READY:", ready)
print("POSSIBLE:", possible)
print("ACTIVE:", active)

r = len(ready) if ready else 0
p = len(possible) if possible else 0
print("ready count:", r, "possible count:", p, "ready-possible:", r - p, ">=2?", (r - p) >= 2)
