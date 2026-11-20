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
#   fixcachelocality.py <leaderip> <pool> <myhost> wait (QSD5.352 r10, zpooltoimport.py) the same, but the cluster info
#                                                       is read again every 15 s (3 min at most) until it lists the pool
#   fixcachelocality.py rmcache <pool> <disk>           remove one cache vdev by name or GUID (DGsetPool updatecache,
#                                                       when the old cache disk has no /dev/disk/by-id link any more)
#   fixcachelocality.py rmdead <pool>                   remove every UNAVAIL/REMOVED/FAULTED cache vdev (updatecache)
import os
import re
import sys
import json
import subprocess
import time

WAIT_TRIES = 12           # QSD5.352 r10 (QC 631): wait mode, 12 x 15 s = 3 minutes at most
WAIT_STEP = 15
ADD_TRIES = 3            # QSD5.352 r10h: zpool add of the local cache, 'udevadm settle' + ADD_WAIT s between tries
ADD_WAIT = 5
# QSD5.352 r10r (QC 580.1, r10q x1 twice): right after the take-over import the cluster info listed P1 but no free disk
# of the new owner yet (zfs2 /root/fixcachelocality.log 17:38: five 'pools {}' reads, then 'no free or spare cache
# disk on dhcp178871'), so the wait-mode run kept the remote cache (on the stopped node's disk) and ended; nothing ran
# again until the next take-over two hours later, when the same disk was found at once.  Wait mode (container flavour)
# now reads the info again up to PICK_TRIES times, PICK_STEP s apart, while no local disk can be picked, as long as the
# pool is still imported here, owned by this node and has no working local cache.
PICK_TRIES = int(os.environ.get('FCL_PICK_TRIES', '12'))
PICK_STEP = int(os.environ.get('FCL_PICK_STEP', '15'))

sys.path.insert(0, '/TopStor')

DEAD_STATES = ('UNAVAIL', 'REMOVED', 'FAULTED')


def resolve_by_id(disk_substr):
    out = subprocess.run(['ls', '/dev/disk/by-id/'], stdout=subprocess.PIPE).stdout.decode()
    for line in out.splitlines():
        if disk_substr in line and 'part' not in line:
            return line
    return None


# QSD5.352 r10m (QC proof 10l N5, 763.2): after a take-over the 3 adds of the local cache failed within 15 s with
# 'missing link: sdj was partitioned but /dev/disk/by-id/<disk>-part1 is missing' (the link 7 min late at host load 15; r10n
# V-4: in the container the link is made by cdiskids.sh, not udev) and
# nothing tried again: the pool stayed without a cache.  In wait mode (the background run after a take-over import) a
# failed add whose error is a late or missing device link now waits for the disk's -part1 link (every LATE_STEP s, at most
# LATE_WAIT s), then adds the whole disk again and, if that still misses the link, the -part1 partition itself.  It stops
# when the pool is no longer imported here or has got a working cache meanwhile.  Every step is logged.
LATE_WAIT = 900
LATE_STEP = 30
LATE_ERRORS = ('missing link', 'failed to detect device', 'is currently unavailable', 'no such device', 'resource busy')


def late_link_error(err):
    return any(e in str(err) for e in LATE_ERRORS)


def _imported_here(pool):
    return os.path.exists('/proc/spl/kstat/zfs/' + pool)


# r10n (validator 10m V-3, MEDIUM): in the container flavour every node shares one kernel, so the kstat above exists
# whichever node imported the pool: a take-back by the returning owner within the 15 min was not seen and this node could
# add ITS disk as the cache of a pool it no longer owns (a remote cache again).  Each round now also reads the owner
# written on the pool (/pace/cpoolowner.sh of <pool>, as zpooltoimport's poolishere()): it must name this node.
def _owner(pool):
    """The owner written on the pool ('' when it cannot be read: the pool is not ONLINE/DEGRADED, or the call failed)."""
    try:
        r = subprocess.run(['/pace/cpoolowner.sh', 'of', pool], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=30)
        return r.stdout.decode('utf-8', 'replace').strip()
    except Exception:
        return ''


# r10n (validator 10m V-4, MEDIUM): the container's /dev is a tmpfs whose by-id links only /pace/cdiskids.sh makes (sysfs
# only, cheap), once per iscsiwatchdog loop -- minutes apart under load; 'udevadm settle' does nothing there (no udev in
# the container).  The container flavour runs cdiskids.sh before each add try and each late-add round.
def _links():
    try:
        subprocess.run(['timeout', '20', '/pace/cdiskids.sh'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass


def late_add(pool, disk, err, owner=None):
    # the device added (by-id whole disk or its -part1) or None; container flavour only (r10n V-2)
    part = '/dev/disk/by-id/' + disk + '-part1'
    print(f"fixcachelocality: {pool}: the add of {disk} failed on a device link ({str(err)[:160]}); waiting for {part} (at most {LATE_WAIT} s)")
    t0 = time.time()
    while time.time() - t0 <= LATE_WAIT:
        if not _imported_here(pool):
            print(f"fixcachelocality: {pool} is no longer imported here, no late add")
            return None
        if owner:
            who = _owner(pool)
            if who and who not in (owner, '-'):
                print(f"fixcachelocality: {pool} is owned by {who} now, not by {owner}: no late add")
                return None
            if who != owner:
                print(f"fixcachelocality: {pool}: owner not readable as {owner} [{who}], no add in this round")
                time.sleep(LATE_STEP)
                continue
        live = [(n, s) for n, g, s in cache_entries(pool) if s not in DEAD_STATES]
        if live:
            print(f"fixcachelocality: {pool} has a working cache {live} meanwhile, no late add")
            return None
        _links()                                   # r10n (V-4): the links from sysfs now
        if os.path.exists(part):
            for dev in (disk, part):
                r = subprocess.run(['/sbin/zpool', 'add', '-f', pool, 'cache', dev], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                if r.returncode == 0:
                    print(f"fixcachelocality: late add of {dev} to {pool} worked after {int(time.time() - t0)} s")
                    return dev
                err = r.stderr.decode('utf-8', 'replace').strip()
                print(f"fixcachelocality: late add of {dev} to {pool} failed after {int(time.time() - t0)} s: {err[:200]}")
                if not late_link_error(err):
                    return None                    # a real refusal: not retried
        time.sleep(LATE_STEP)
    print(f"fixcachelocality: {pool}: {part} did not come (or the add kept failing) within {LATE_WAIT} s, no cache added")
    return None


def _cache_section(text, was_name=False):
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
            name = tok[0]
            # a vdev missing at import is listed by its GUID: "<guid> UNAVAIL 0 0 0 was /dev/disk/by-id/<disk>-part1";
            # with was_name (plain `zpool status`, not -g) the disk of the 'was' path is the name, so the cluster's disk
            # name (DGsetPool updatecache old disk, the remote cache of the info) still matches it
            if was_name and name.isdigit() and len(tok) >= 3 and tok[-2] == 'was':
                was = tok[-1].rsplit('/', 1)[-1]
                name = was[:-len('-part1')] if was.endswith('-part1') else was
            entries.append((name, tok[1] if len(tok) > 1 else ''))
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
    names = _cache_section(status, was_name=True)
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


SCSIRE = re.compile(r'scsi-[0-9A-Za-z]+')
SDRE = re.compile(r'\b(sd[a-z]+)[0-9]*\b')


def iscontainer():
    # the same test as flavor.sh
    return os.path.exists('/.dockerenv') or os.path.exists('/run/.containerenv') or os.path.isdir('/sys/class/net/eth10')


def _zout(args, t=60):
    """stdout of a zpool command, None when it failed or timed out ('no pools available' is an empty answer)."""
    try:
        r = subprocess.run(['timeout', str(t)] + args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except Exception:
        return None
    out = (r.stdout or b'').decode('utf-8', 'replace')
    err = (r.stderr or b'').decode('utf-8', 'replace')
    if r.returncode == 0 or (out.strip() == '' and 'no pools available' in err):
        return out
    return None


def _named(did, d, text):
    ids = set(m.group(0) for m in SCSIRE.finditer(text))
    sds = set(m.group(1) for m in SDRE.finditer(text))
    return did in ids or str(d.get('actualdisk', '')) in ids or str(d.get('devname', '-')) in sds


def reserved_disks(leaderip, info, owner):
    """QSD5.352 r10h pass 2 (validator G6, same class as QC proof 10g finding 7): {disk: why} of the disks of `owner` that
    the cluster info lists as free but that must not become a cache: a disk 'zpool status' names (any pool, also the
    'was /dev/disk/by-id/<disk>-part1' of a REMOVED / UNAVAIL leg that came back), or a member, in 'zpool import', of a
    pool this cluster expects (ActPool/ or poolnxt/) that is not imported.  'zpool add -f' overrides ZFS's own "is part
    of exported pool" refusal, so such a leg became a cache disk and its pool lost it.  A failed or timed-out zpool read
    holds every candidate (fail closed: the remote cache is then kept).  Container flavour only (physical: {})."""
    if not iscontainer():
        return {}
    cands = dict((did, d) for did, d in info.get('disks', {}).items()
                 if d.get('host') == owner and str(d.get('pool', '')) in ('pree', ''))
    if not cands:
        return {}
    status = _zout(['/sbin/zpool', 'status'], 60)
    if status is None:
        return dict((did, 'unknown: zpool status gave no answer') for did in cands)
    why = {}
    for did, d in cands.items():
        if _named(did, d, status):
            why[did] = 'named in zpool status'
    known = set()
    try:
        from etcdget import etcdget as get
        for pfx in ('ActPool/', 'poolnxt/'):
            for row in get(leaderip, pfx, '--prefix'):
                if isinstance(row, (list, tuple)) and len(row) > 1 and str(row[0]).startswith(pfx):
                    known.add(str(row[0])[len(pfx):])
    except Exception:
        pass
    imported = set((_zout(['/sbin/zpool', 'list', '-H', '-o', 'name'], 30) or '').split()) | set(info.get('pools', {}).keys())
    pending = set(p for p in known if p and p not in imported)
    if not pending:
        return why
    scan = _zout(['/sbin/zpool', 'import'], 90)
    if scan is None:
        for did in cands:
            why.setdefault(did, 'unknown: zpool import gave no answer (pending ' + ','.join(sorted(pending)) + ')')
        return why
    secs = []
    for line in scan.split('\n'):
        w = line.split()
        if len(w) >= 2 and w[0] == 'pool:':
            secs.append([w[1], ''])
        elif secs:
            secs[-1][1] += line + '\n'
    for did, d in cands.items():
        if did in why:
            continue
        for name, sec in secs:
            if name in pending and _named(did, d, sec):
                why[did] = 'member of ' + name + ' waiting to import'
                break
    return why


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


def repick(leaderip, pool, myhost, why, notlocal=()):
    """r10r (580.1): wait mode, container flavour: (disk, reason, info) once the cluster info offers a local cache disk
    for `pool` on `myhost`; (None, reason, None) after PICK_TRIES rounds or when the pool left this node / got a working
    local cache meanwhile."""
    from allphysicalinfo import getall, initallphy
    for n in range(PICK_TRIES):
        print(f"fixcachelocality: {pool}: {why}; reading the cluster info again in {PICK_STEP} s (round {n + 1} of {PICK_TRIES})")
        time.sleep(PICK_STEP)
        if not _imported_here(pool):
            return None, f"pool {pool} is no longer imported here, no cache added", None
        who = _owner(pool)
        if who and who not in (myhost, '-'):
            return None, f"pool {pool} is owned by {who} now, not by {myhost}: no cache added", None
        entries = cache_entries(pool)
        try:
            initallphy(leaderip)
            info = getall(leaderip)
        except Exception as e:
            why = f"cluster info not readable ({str(e)[:80]})"
            continue
        pool_data = info.get('pools', {}).get(pool)
        if not pool_data:
            why = f"pool {pool} not in the cluster info"
            continue
        cache_disks = []
        for raid_id in pool_data.get('raids', []):
            if raid_id.split('_')[0] == 'cache':
                cache_disks.extend(info.get('raids', {}).get(raid_id, {}).get('disks', []))
        remote = [d for d in cache_disks if info.get('disks', {}).get(d, {}).get('host') != myhost]
        # r10r (validator G-6): the caches main() found remote (notlocal) never count as local, also when the re-read info
        # lacks the pool's cache raid (info being rebuilt) and so does not list them as remote
        live_local = [nm for nm, g, st in entries if st not in DEAD_STATES and nm not in notlocal
                      and not any(_same_disk(d, nm) for d in remote)]
        if live_local:
            return None, f"pool {pool} has a working local cache {live_local} meanwhile, no disk added", None
        exclude = set(cache_disks) | set(nm for nm, g, st in entries)
        held = reserved_disks(leaderip, info, myhost)
        if held:
            print(f"fixcachelocality: not used as cache (reserved): {sorted(held.items())}")
            exclude = exclude | set(held)
        new, why = pick_cache_disk(info, myhost, pool, exclude, spare_list(leaderip))
        if new:
            print(f"fixcachelocality: {pool}: local cache disk {new} found in round {n + 1} ({why})")
            return new, why, info
    return None, f"{why} (after {PICK_TRIES} more reads of the cluster info)", None


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
    # QSD5.352 r10 (QC 631): right after a take-over import the cluster info still listed the pool under its old owner
    # only (or not at all): 'not found in the cluster info, nothing done' and the cache stayed UNAVAIL for good.  With
    # 'wait' (zpooltoimport.py, run in the background) the info is read again every WAIT_STEP s until the pool shows up,
    # WAIT_TRIES times at most.
    wait = len(sys.argv) >= 5 and sys.argv[4] == 'wait'
    tries = WAIT_TRIES if wait else 1
    pool_data, info = None, {}
    for n in range(tries):
        if n:
            time.sleep(WAIT_STEP)
        initallphy(leaderip)
        info = getall(leaderip)
        pool_data = info['pools'].get(pool)
        if pool_data:
            break
    if not pool_data:
        print(f"fixcachelocality: pool {pool} not found in the cluster info, nothing done" + (f" (after {tries} tries)" if wait else ''))
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
    # QSD5.352 r10h (QC proof 10g s3:q 584.1): the remote cache used to be removed FIRST; the add of the local disk then
    # failed ('cannot label sdd: failed to detect device': a disk whose iSCSI session had just been logged in again) and
    # the pool was left WITHOUT a cache.  Now: a lost cache (UNAVAIL / REMOVED / FAULTED) serves nothing and is removed
    # first; a remote cache that still works (ONLINE) is removed only AFTER the local one was added (add first); the add
    # is tried up to ADD_TRIES times with 'udevadm settle' in between; no local disk, or a failed add, keeps it.
    left = []
    dead = [(n, g, st) for n, g, st in bad if st in DEAD_STATES]
    working = [(n, g, st) for n, g, st in bad if st not in DEAD_STATES]
    for name, guid, state in dead:
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
        held = reserved_disks(leaderip, info, myhost)      # r10h pass 2 (G6)
        if held:
            print(f"fixcachelocality: not used as cache (reserved): {sorted(held.items())}")
            exclude = exclude | set(held)
        new, why = pick_cache_disk(info, myhost, pool, exclude, spares)
        if not new and wait and iscontainer() and PICK_TRIES > 0:   # r10r (580.1): the info may not list the disk yet
            new, why, info2 = repick(leaderip, pool, myhost, why, badnames)
            if new:
                info = info2
                spares = spare_list(leaderip)
    added = None
    if new:
        resolved = resolve_by_id(new)
        if resolved:
            err = ''
            for n in range(ADD_TRIES):
                if n:
                    try:
                        subprocess.run(['udevadm', 'settle', '--timeout=30'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    except Exception:
                        pass                       # no udevadm: the wait alone
                    time.sleep(ADD_WAIT)
                    if iscontainer():
                        _links()                   # r10n (V-4): container: no udev, the links come from cdiskids.sh
                r = subprocess.run(['/sbin/zpool', 'add', '-f', pool, 'cache', resolved],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                if r.returncode == 0:
                    added = resolved
                    break
                err = r.stderr.decode('utf-8', 'replace').strip()
                print(f"fixcachelocality: zpool add {pool} cache {resolved} failed (try {n + 1} of {ADD_TRIES}): {err}")
            # r10n (validator 10m V-2): the late wait is container flavour only (the physical path is as before round 10m)
            if not added and wait and iscontainer() and late_link_error(err):
                added = late_add(pool, resolved, err, myhost)  # r10m (N5), r10n (V-3: owner checked each round)
            if added:
                print(f"fixcachelocality: added local disk {added} ({why}) as new cache for {pool} (add first)")
                if any(_same_disk(s, new) for s in spares):    # a spare in use is no spare any more
                    subprocess.run(['/usr/bin/python3', '/TopStor/cachedisks.py', 'del', leaderip]
                                   + [s for s in spares if _same_disk(s, new)], cwd='/TopStor')
        else:
            print(f"fixcachelocality: chosen disk {new} has no /dev/disk/by-id link on {myhost}, not added")
    else:
        print(f"fixcachelocality: {why}")
    for name, guid, state in working:
        if added or keep:
            ok, how = remove_cache(pool, guid or name, entries)
            print('fixcachelocality: ' + how)
            if not ok:
                left.append(name)
        else:
            print(f"fixcachelocality: the remote cache {name} ({state}) of {pool} is kept: no local cache could be added")
            left.append(name)

    still = [n for n, g, s in cache_entries(pool)]
    if added:
        print(f"fixcachelocality: pool {pool} cache now {still}")
    elif left:
        print(f"fixcachelocality: pool {pool} keeps cache {still} (the not-local one(s) {left} kept or not removable)")
    elif still:
        print(f"fixcachelocality: pool {pool} cache now {still}")
    else:
        print(f"fixcachelocality: pool {pool} now has no cache")


if __name__ == '__main__':
    main()
