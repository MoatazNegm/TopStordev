#!/usr/bin/python3
# Runs after a pool import (DGsetPool's "import" branch and pace/zpooltoimport.py after a take-over). If the pool
# that just got imported here has a cache (L2ARC) vdev that lives on a different host than the one now owning the
# pool - or that is lost (UNAVAIL/REMOVED/FAULTED) - that disk is useless as a read cache: remove it and add a
# local disk instead.
#
# QSD5.351 (QC 631 i2): which local disk (pick_cache_disk, also used by fapi's pools/updatecache):
#   1. a spare cache disk of this host (etcd `cachespares`, or a disk putzpool lists in the 'cache' raid of 'pree'),
#   2. else the smallest free disk of this host that is strictly smaller than the pool's smallest data disk,
#   3. else the old rule: a free disk at the smallest size tier, strictly smaller than the rest of the host's free
#      disks.
# Before, only rule 3 existed (one free small disk never qualified, the pool's data disks were never compared, the
# spare list was never read).  A remote cache disk that cannot be resolved here is removed by its vdev GUID
# (`zpool status -g`), and the log says what really happened.
#
#   fixcachelocality.py <leaderip> <pool> <myhost>      relocate after an import
#   fixcachelocality.py rmcache <pool> <disk>           remove one cache vdev by name or GUID (DGsetPool updatecache,
#                                                       when the old cache disk has no /dev/disk/by-id link any more)
#   fixcachelocality.py rmdead <pool>                   remove every UNAVAIL/REMOVED/FAULTED cache vdev (updatecache)
import sys
import json
import subprocess

sys.path.insert(0, '/TopStor')

DEAD_STATES = ('UNAVAIL', 'REMOVED', 'FAULTED')


def resolve_by_id(disk_substr):
    out = subprocess.run(['ls', '/dev/disk/by-id/'], stdout=subprocess.PIPE).stdout.decode()
    for line in out.splitlines():
        if disk_substr in line and 'part' not in line:
            return line
    return None


def _cache_section(text):
    """The device lines under the 'cache' header of `zpool status` as [(name, state)]."""
    entries = []
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.strip() != 'cache':
            continue
        indent = len(line) - len(line.lstrip())
        for nxt in lines[i + 1:]:
            if not nxt.strip():
                break
            if len(nxt) - len(nxt.lstrip()) <= indent:
                break
            tok = nxt.split()
            entries.append((tok[0], tok[1] if len(tok) > 1 else ''))
        break
    return entries


def cache_entries(pool, status=None, gstatus=None):
    """[(name, guid, state)] of the pool's cache vdevs: `zpool status` and `zpool status -g` list them in the same
    order, so the n-th name pairs with the n-th GUID."""
    if status is None:
        status = subprocess.run(['/sbin/zpool', 'status', pool], stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL).stdout.decode('utf-8', 'replace')
    if gstatus is None:
        gstatus = subprocess.run(['/sbin/zpool', 'status', '-g', pool], stdout=subprocess.PIPE,
                                 stderr=subprocess.DEVNULL).stdout.decode('utf-8', 'replace')
    names = _cache_section(status)
    guids = _cache_section(gstatus)
    res = []
    for n, (name, state) in enumerate(names):
        guid = guids[n][0] if n < len(guids) and guids[n][0].isdigit() else ''
        res.append((name, guid, state))
    return res


def _same_disk(disk, name):
    disk, name = str(disk), str(name)
    if not disk or not name:
        return False
    return disk == name or disk[-20:] in name or name[-20:] in disk


def remove_cache(pool, disk, entries=None):
    """Remove the cache vdev of `pool` that is `disk` (a disk name, by-id name or GUID). Returns (ok, how)."""
    if entries is None:
        entries = cache_entries(pool)
    for name, guid, state in entries:
        if not ((guid and str(disk) == guid) or _same_disk(disk, name)):
            continue
        targets = [guid] if guid else []
        resolved = resolve_by_id(name)
        if resolved:
            targets.append(resolved)
        targets.append(name)
        err = ''
        for t in targets:
            r = subprocess.run(['/sbin/zpool', 'remove', pool, t], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if r.returncode == 0:
                return True, 'removed cache ' + name + ' (' + state + ') of ' + pool + ' by ' + t
            err = r.stderr.decode('utf-8', 'replace').strip()
        return False, 'zpool remove ' + pool + ' ' + name + ' failed: ' + err
    return False, str(disk) + ' is not a cache vdev of ' + pool


def _size(disk_info):
    try:
        return float(disk_info.get('size', 0))
    except (TypeError, ValueError):
        return 0.0


def spare_list(leaderip):
    """The etcd `cachespares` list (disk names), [] when it is missing or unreadable."""
    try:
        from etcdget import etcdget as get
        res = get(leaderip, 'cachespares')
        raw = res[0] if isinstance(res, list) and res else res
        if not raw or raw == '_1':
            return []
        val = json.loads(str(raw).replace("'", '"'))
        return [str(x) for x in val] if isinstance(val, list) else []
    except Exception:
        return []


def pick_cache_disk(info, owner, pool, exclude=(), spares=()):
    """(disk, reason) of the local disk to use as the read cache of `pool` on `owner`; (None, reason) if none."""
    exclude = set(exclude)
    local = {}
    for did, d in info.get('disks', {}).items():
        if d.get('host') != owner or did in exclude:
            continue
        if str(d.get('pool', '')) not in ('pree', ''):
            continue                                # in a pool already
        if str(d.get('status', '')) not in ('free', 'cache') and str(d.get('raid', '')) not in ('free', 'cache'):
            continue
        if _size(d) <= 0:
            continue
        local[did] = d
    # 1. a spare cache disk of this host
    spare_ids = [did for did, d in local.items()
                 if did in spares or any(_same_disk(s, did) for s in spares)
                 or str(d.get('status', '')) == 'cache' or str(d.get('raid', '')) == 'cache']
    if spare_ids:
        best = min(spare_ids, key=lambda x: (_size(local[x]), x))
        return best, 'spare cache disk'
    free = {did: _size(d) for did, d in local.items()}
    if not free:
        return None, 'no free or spare cache disk on ' + owner
    # 2. a free disk smaller than the pool's smallest data disk
    data_sizes = []
    pool_data = info.get('pools', {}).get(pool, {})
    for raid_id in pool_data.get('raids', []):
        if raid_id.split('_')[0] in ('cache', 'free', 'spares', 'spare', 'logs', 'log'):
            continue
        for did in info.get('raids', {}).get(raid_id, {}).get('disks', []):
            s = _size(info.get('disks', {}).get(did, {}))
            if s > 0:
                data_sizes.append(s)
    if data_sizes:
        smaller = [did for did, s in free.items() if s < min(data_sizes)]
        if smaller:
            best = min(smaller, key=lambda x: (free[x], x))
            return best, 'free disk smaller than the pool data disks'
    # 3. the old rule: smaller than the rest of the host's free disks
    smallest = min(free.values())
    if smallest < max(free.values()):
        best = min([d for d, s in free.items() if s == smallest])
        return best, 'free disk smaller than the rest'
    return None, ('no spare cache disk on ' + owner + ', and no free disk there is smaller than the pool data disks'
                  ' or than the rest')


def main():
    if len(sys.argv) >= 4 and sys.argv[1] == 'rmcache':
        ok, how = remove_cache(sys.argv[2], sys.argv[3])
        print('fixcachelocality: ' + how)
        sys.exit(0 if ok else 1)
    if len(sys.argv) >= 3 and sys.argv[1] == 'rmdead':
        bad = 0
        for name, guid, state in cache_entries(sys.argv[2]):
            if state in DEAD_STATES:
                ok, how = remove_cache(sys.argv[2], guid or name)
                print('fixcachelocality: ' + how)
                bad += (not ok)
        sys.exit(1 if bad else 0)
    if len(sys.argv) < 4:
        return
    leaderip = sys.argv[1]
    pool = sys.argv[2]
    myhost = sys.argv[3]

    from allphysicalinfo import getall, initallphy
    initallphy(leaderip)
    info = getall(leaderip)

    pool_data = info['pools'].get(pool)
    if not pool_data:
        print(f"fixcachelocality: pool {pool} not found in the cluster info, nothing done")
        return

    cache_disks = []
    for raid_id in pool_data.get('raids', []):
        if raid_id.split('_')[0] == 'cache':
            cache_disks.extend(info['raids'].get(raid_id, {}).get('disks', []))
    entries = cache_entries(pool)

    if not cache_disks and not entries:
        print(f"fixcachelocality: pool {pool} has no cache vdev, nothing to do")
        return

    remote = [d for d in cache_disks if info['disks'].get(d, {}).get('host') != myhost]
    bad = []                                       # zpool entries to remove: a remote disk, or a lost one
    for name, guid, state in entries:
        if state in DEAD_STATES or any(_same_disk(d, name) for d in remote):
            bad.append((name, guid, state))
    if not bad and not entries:                    # the info lists a remote cache that zpool status does not show
        bad = [(d, '', '') for d in remote]
    if not bad:
        print(f"fixcachelocality: pool {pool}'s cache is already local to {myhost}")
        return

    print(f"fixcachelocality: pool {pool}'s cache {[(n, s) for n, g, s in bad]} is not local to {myhost}, relocating")
    left = []
    for name, guid, state in bad:
        ok, how = remove_cache(pool, guid or name, entries)
        print('fixcachelocality: ' + how)
        if not ok:
            left.append(name)

    badnames = set(n for n, g, s in bad)
    keep = [n for n, g, s in entries if n not in badnames and s not in DEAD_STATES]
    exclude = set(cache_disks) | set(n for n, g, s in entries)
    spares = spare_list(leaderip)
    if keep:                                       # a healthy local cache is left: no second one
        new, why = None, f"pool {pool} keeps its local cache {keep}, no disk added"
    else:
        new, why = pick_cache_disk(info, myhost, pool, exclude, spares)
    added = None
    if new:
        resolved = resolve_by_id(new)
        if resolved:
            r = subprocess.run(['/sbin/zpool', 'add', '-f', pool, 'cache', resolved],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if r.returncode == 0:
                added = resolved
                print(f"fixcachelocality: added local disk {resolved} ({why}) as new cache for {pool}")
                if any(_same_disk(s, new) for s in spares):    # a spare in use is no spare any more
                    subprocess.run(['/usr/bin/python3', '/TopStor/cachedisks.py', 'del', leaderip]
                                   + [s for s in spares if _same_disk(s, new)], cwd='/TopStor')
            else:
                print(f"fixcachelocality: zpool add {pool} cache {resolved} failed: "
                      + r.stderr.decode('utf-8', 'replace').strip())
        else:
            print(f"fixcachelocality: chosen disk {new} has no /dev/disk/by-id link on {myhost}, not added")
    else:
        print(f"fixcachelocality: {why}")

    still = [n for n, g, s in cache_entries(pool)]
    if added:
        print(f"fixcachelocality: pool {pool} cache now {still}")
    elif left:
        print(f"fixcachelocality: pool {pool} keeps cache {still} (the not-local one(s) {left} could not be removed)")
    elif still:
        print(f"fixcachelocality: pool {pool} cache now {still}")
    else:
        print(f"fixcachelocality: pool {pool} now has no cache")


if __name__ == '__main__':
    main()
