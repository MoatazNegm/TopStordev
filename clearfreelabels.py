#!/usr/bin/python3
# clearfreelabels.py <leaderip> <disk> [disk ...]   (called by DGsetPool right before "zpool create" on exactly these disks)
#
# Disks that were part of an old, destroyed or never exported pool (a reused/reset VM, a disk moved from another box) keep that
# pool's ZFS labels.  The cluster lists them as free (pree), but the product's own import scan ("zpool import" in the pace loopers)
# then finds the stale pool and the kernel's try-import holds its member partitions exclusively for a moment; "zpool create -f"
# opens the whole disk with O_EXCL and fails: "<disk> is in use and contains a unknown filesystem" (test 26 step 717, QSD5.314).
#
# The labels are cleared ONLY when every check passes for that disk (otherwise it is left untouched and zpool create decides):
#  - it is a /dev/disk/by-id block device, not mounted, no swap, no holder (dm/md), not the disk of / or /boot;
#  - no pool imported on this node uses it (zpool list -vHPL);
#  - the cluster reports it free: it is in a "pree" pool of some hosts/<host>/current and in no other pool of any host;
#    no answer from etcd = not free.
# Every action is written to /root/dglabelclear.
import sys, os, json, subprocess, glob
from etcdgetpy import etcdget as get

LOG = '/root/dglabelclear'


def log(*a):
    with open(LOG, 'a') as f:
        f.write(' '.join(str(x) for x in a) + '\n')


def run(cmd):
    r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
    return r.returncode, r.stdout.decode(errors='replace'), r.stderr.decode(errors='replace')


def clusterview(leaderip):
    """(free, used): disk names the cluster reports free / in a pool; None when etcd gives no usable answer."""
    hosts = get(leaderip, 'hosts/', '--prefix')
    free, used, seen = set(), set(), 0
    for kv in hosts:
        if not isinstance(kv, tuple) or not kv[0].endswith('/current'):
            continue
        try:
            pools = json.loads(kv[1])
        except Exception:
            return None
        seen += 1
        for pool in pools:
            target = free if pool.get('name') == 'pree' else used
            for raid in pool.get('raidlist', []):
                for disk in raid.get('disklist', []):
                    for k in ('name', 'actualdisk'):
                        if disk.get(k):
                            target.add(disk[k])
    return (free, used) if seen else None


def systemdisks():
    """the whole disks (sdX) of /, /boot and every mounted or swap device"""
    rc, out, _ = run(['lsblk', '-nrpo', 'PKNAME,NAME,MOUNTPOINT,FSTYPE'])
    sysd = set()
    for line in out.splitlines():
        f = line.split(' ')
        if len(f) >= 3 and (f[2] or (len(f) > 3 and f[3] == 'swap')):
            sysd.add(f[0] or f[1])
    return sysd


def main(leaderip, disks):
    view = clusterview(leaderip)
    if view is None:
        log('no cluster view from', leaderip, '- nothing cleared', disks)
        return
    free, used = view
    rc, imported, _ = run(['/sbin/zpool', 'list', '-vHPL'])
    if rc != 0:
        log('zpool list failed - nothing cleared', disks)
        return
    sysd = systemdisks()
    for disk in disks:
        name = os.path.basename(disk)
        path = '/dev/disk/by-id/' + name
        if not os.path.exists(path):
            log(name, 'skip: no such by-id device')
            continue
        dev = os.path.realpath(path)
        base = os.path.basename(dev)
        if name not in free or name in used:
            log(name, dev, 'skip: not reported free by the cluster')
            continue
        if dev in sysd:
            log(name, dev, 'skip: system/mounted disk')
            continue
        if any(os.listdir(h) for h in glob.glob('/sys/block/' + base + '/holders') + glob.glob('/sys/block/' + base + '/' + base + '*/holders')):
            log(name, dev, 'skip: has holders')
            continue
        if any(w == dev or (w.startswith(dev) and w[len(dev):].isdigit()) for line in imported.splitlines() for w in line.split()):
            log(name, dev, 'skip: used by an imported pool')
            continue
        for part in [dev] + sorted(glob.glob(dev + '[0-9]*')):
            rc, out, _ = run(['blkid', '-p', '-s', 'TYPE', '-o', 'value', part])
            if out.strip() != 'zfs_member':
                continue
            rc, out, err = run(['/sbin/zpool', 'labelclear', '-f', part])
            log(name, part, 'labelclear rc', rc, err.strip())


if __name__ == '__main__':
    if len(sys.argv) > 2:
        try:
            main(sys.argv[1], sys.argv[2:])
        except Exception as e:
            log('error', e)
