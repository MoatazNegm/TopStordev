#!/usr/bin/python3
"""
RAID 10 configuration module.
Computes available RAID 10 options from free disks and selects
the best disks using the same smart balancing logic as fastselect.py
to ensure high availability across nodes.

RAID 10 = striped mirrors. Requires an even number of disks (minimum 4).

Two modes:
 - Uniform: all pairs use the same (minimum) disk size.
   Useable = (diskcount / 2) * min_disk_size.
 - Matched: each mirror pair uses same-size disks, different pairs can differ.
   Useable = sum of each pair's disk size. Maximizes capacity with mixed drives.
   Identified by diskcount matching total paired disks across all size groups.
"""
from fastselect import selectdisks

def getraid10(single, diskdict):
 """Compute available RAID 10 configurations from free disk groups.
 
 Args:
   single: dict keyed by disk size, values are lists of free disk names
   diskdict: full disk info dict (name -> {host, size, raid, ...})
 
 Returns:
   dict keyed by useable capacity, values are dicts with disk/diskcount/others/hosts info
   Output format is consistent with all other RAID types.
 """
 group = 4  # minimum disks for RAID 10
 theraid = dict()

 # Uniform mode: all mirror pairs treat disks at same (minimum) size
 for size in single:
  otherslist = []
  hosts = set()
  othershosts = set()
  posdiskc = 0
  for others in single:
   if others > size:
    posdiskc += len(single[others])
    otherslist.append(others)
    for dsk in single[others]:
     othershosts.add(diskdict[dsk]['host'])
  total = posdiskc + len(single[size])
  for dsk in single[size]:
   hosts.add(diskdict[dsk]['host'])
  if total >= group:
   diskcount = group
   while diskcount <= total:
    base = round(size * (diskcount // 2), 2)
    theraid[base] = {'disk':size, 'diskcount':diskcount, 'others':otherslist, 'hosts': list(hosts), 'othershosts': list(othershosts)}
    diskcount += 2

 # Matched mode: each pair uses same-size disks, pairs can be different sizes
 sizegroups = {}
 allhosts = set()
 totalpairs = 0
 totaldisks = 0
 totaluseable = 0
 for size in single:
  pairs = len(single[size]) // 2
  if pairs > 0:
   sizegroups[size] = pairs
   totalpairs += pairs
   totaldisks += pairs * 2
   totaluseable += round(size * pairs, 2)
   for dsk in single[size]:
    allhosts.add(diskdict[dsk]['host'])
 totaluseable = round(totaluseable, 2)
 if totalpairs >= 2 and totaldisks >= group and totaluseable not in theraid:
  theraid[totaluseable] = {
   'disk': min(sizegroups.keys()),
   'diskcount': totaldisks,
   'others': sorted([s for s in sizegroups.keys() if s > min(sizegroups.keys())]),
   'hosts': list(allhosts),
   'othershosts': list(allhosts)
  }

 return theraid


def _is_matched(fdisks, fdisksinfo):
 """Detect if this RAID 10 entry is a matched-mode config.
 
 Matched mode: the diskcount equals the total of all paired free disks
 across multiple size groups. In uniform mode, others list sizes > disk,
 and diskcount can grow beyond what same-size groups provide.
 """
 mindisk = fdisks['disk']
 diskcount = fdisks['diskcount']
 # Count how many pairs each size group can form from free disks
 sizegroups = {}
 for d, info in fdisksinfo.items():
  if info.get('raid') == 'free':
   sz = info['size']
   if sz not in sizegroups:
    sizegroups[sz] = 0
   sizegroups[sz] += 1
 totalpaired = 0
 pairgroups = {}
 for sz, cnt in sizegroups.items():
  pairs = cnt // 2
  if pairs > 0:
   pairgroups[sz] = pairs
   totalpaired += pairs * 2
 # It's matched if we have multiple size groups with pairs and diskcount uses all of them
 return len(pairgroups) >= 2 and diskcount == totalpaired, pairgroups


def interleave_by_host(names, fdisksinfo):
 """Order the selected disks so that consecutive pairs come from different hosts.

 DGsetPool builds the mirrors of a RAID 10 from consecutive disks (disk 1+2, 3+4 ...). The selection is balanced in numbers
 but returned grouped by host (A A A A A B B B B B), which put both halves of most mirrors on one node: the pool is
 not 'highly available - balanced' and a node loss takes whole mirrors with it. Round robin over the hosts (the host with
 most disks first) puts A B A B ... so every pair spans two nodes as far as the numbers allow."""
 groups = {}
 for name in names:
  groups.setdefault(fdisksinfo[name]['host'], []).append(name)
 order = sorted(groups, key=lambda h: -len(groups[h]))
 out = []
 while any(groups.values()):
  for host in order:
   if groups[host]:
    out.append(groups[host].pop(0))
 return out


def selectraid10(leaderip, fdisks, fdisksinfo, addtopool='', excludelst=''):
 """Select the best disks for a RAID 10 configuration.
 
 Automatically detects whether to use matched or uniform mode based
 on the disk entry and available free disks.
 
 Both modes use the smart balancing algorithm from fastselect.py which
 prioritizes host balance (1000x weight) over size uniformity.
 
 Args:
   leaderip: cluster leader IP for etcd queries
   fdisks: dict with 'diskcount' and 'disk' keys
   fdisksinfo: full disk info dict
   addtopool: pool name if adding to existing pool
   excludelst: comma-separated disk names to exclude
 
 Returns:
   comma-separated string of selected disk names, or '' if not enough disks
 """
 diskcount = fdisks['diskcount']
 if diskcount < 4 or diskcount % 2 != 0:
  return ''

 matched, pairgroups = _is_matched(fdisks, fdisksinfo)
 if matched:
  # Matched mode: select disks per size group so each pair is same-size
  all_selected = []
  for size, pairs in pairgroups.items():
   filtered = {d: info for d, info in fdisksinfo.items()
                if info.get('raid') == 'free' and info.get('size') == size}
   group_disks = {'diskcount': pairs * 2, 'disk': size}
   result = selectdisks(leaderip, group_disks, filtered, addtopool, excludelst)
   if not result:
    return ''
   all_selected.extend(interleave_by_host(result.split(','), fdisksinfo))
  return ','.join(all_selected)

 result = selectdisks(leaderip, fdisks, fdisksinfo, addtopool, excludelst)
 if not result:
  return ''
 return ','.join(interleave_by_host(result.split(','), fdisksinfo))

