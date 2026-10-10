#!/usr/bin/python3
"""
RAID 50/60 configuration and disk selection helpers.

RAID50 = striped RAIDZ1 groups (fixed width 3 disks per vdev in this flow).
RAID60 = striped RAIDZ2 groups (fixed width 4 disks per vdev in this flow).

Both configurations require at least 2 parity vdev groups:
 - RAID50 minimum disks: 6 (2 x 3)
 - RAID60 minimum disks: 8 (2 x 4)

Selection is delegated to fastselect.selectdisks so host balancing uses the
same weighted logic used by other RAID paths.
"""

from fastselect import selectdisks


def raidwidth(base, nhosts):
 """Group width: the smallest width >= base that every host can fill equally (3 disks on 2 nodes can never be balanced)."""
 if nhosts < 2:
  return base
 width = base
 while width % nhosts != 0:
  width += 1
 return width


def _hostcount(single, diskdict):
 hosts = set()
 for size in single:
  for dsk in single[size]:
   hosts.add(diskdict[dsk]['host'])
 return len(hosts)


def interleave(selected, diskdict, width):
 """Order the selected disks so that every consecutive group of `width` disks has the same number of disks of each host."""
 perhost = dict()
 for dsk in selected:
  perhost.setdefault(diskdict[dsk]['host'], []).append(dsk)
 nhosts = len(perhost)
 if nhosts < 2 or width % nhosts != 0:
  return list(selected)
 each = width // nhosts
 lists = [perhost[h] for h in sorted(perhost)]
 if any(len(l) != len(lists[0]) for l in lists) or len(lists[0]) % each != 0:
  return list(selected)
 ordered = []
 for pos in range(0, len(lists[0]), each):
  for l in lists:
   ordered += l[pos:pos+each]
 return ordered


def groupwidth(selected, diskdict, base):
 """Width used by fapi and DGsetPool for the disks selected (base 3 for RAID50, 4 for RAID60)."""
 return raidwidth(base, len(set(diskdict[d]['host'] for d in selected)))


def _get_striped_parity(single, diskdict, vdev_width, parity):
 """Build striped parity options in the common raid output format."""
 theraid = dict()
 min_groups = 2
 min_disks = vdev_width * min_groups

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

  for dsk in single[size]:
   hosts.add(diskdict[dsk]['host'])

  total = posdiskc + len(single[size])
  if total < min_disks:
   continue

  max_groups = total // vdev_width
  groups = min_groups
  while groups <= max_groups:
   diskcount = groups * vdev_width
   useable = round(size * (vdev_width - parity) * groups, 2)
   theraid[useable] = {
    'disk': size,
    'diskcount': diskcount,
    'others': otherslist,
    'hosts': list(hosts),
    'othershosts': list(othershosts),
   }
   groups += 1

 return theraid


def getraid50(single, diskdict):
 """Compute available RAID50 configurations from free disk groups."""
 return _get_striped_parity(single, diskdict, vdev_width=raidwidth(3, _hostcount(single, diskdict)), parity=1)


def getraid60(single, diskdict):
 """Compute available RAID60 configurations from free disk groups."""
 return _get_striped_parity(single, diskdict, vdev_width=raidwidth(4, _hostcount(single, diskdict)), parity=2)


def _select_raidx0(leaderip, fdisks, fdisksinfo, vdev_width, addtopool='', excludelst=''):
 """Use fastselect balancing to pick disks, then order them so that each group has an equal number of disks per host."""
 diskcount = fdisks.get('diskcount', 0)
 selected = selectdisks(leaderip, fdisks, fdisksinfo, addtopool, excludelst)
 if len(selected) < 1:
  return ''
 chosen = selected.split(',')
 width = groupwidth(chosen, fdisksinfo, vdev_width)
 if diskcount < width * 2 or diskcount % width != 0 or len(chosen) % width != 0:
  return ''
 return ','.join(interleave(chosen, fdisksinfo, width))


def raidwidthof(redundancy, selected, fdisksinfo):
 """Width token for DGsetPool: raid50w4, addraid60w4 ... computed from the disks fapi selected."""
 base = 3 if 'raid50' in redundancy else 4
 return groupwidth(selected, fdisksinfo, base)


def selectraid50(leaderip, fdisks, fdisksinfo, addtopool='', excludelst=''):
 """Select RAID50 disks using the same balancing engine as other RAIDs."""
 return _select_raidx0(leaderip, fdisks, fdisksinfo, vdev_width=3, addtopool=addtopool, excludelst=excludelst)


def selectraid60(leaderip, fdisks, fdisksinfo, addtopool='', excludelst=''):
 """Select RAID60 disks using the same balancing engine as other RAIDs."""
 return _select_raidx0(leaderip, fdisks, fdisksinfo, vdev_width=4, addtopool=addtopool, excludelst=excludelst)
