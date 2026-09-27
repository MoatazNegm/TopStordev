#!/usr/bin/python3
# Runs after a pool import (see DGsetPool's "import" branch). If the pool that
# just got imported here has a cache (L2ARC) vdev that lives on a different
# host than the one now owning the pool, that disk is no longer local -
# reachable only over the network - so it's worse than useless as a read
# cache. Swap it for a spare cache disk that actually lives on this host,
# if one is available.
import sys
import subprocess

sys.path.insert(0, '/TopStor')
from allphysicalinfo import getall, initallphy


def resolve_by_id(disk_substr):
    out = subprocess.run(['ls', '/dev/disk/by-id/'], stdout=subprocess.PIPE).stdout.decode()
    for line in out.splitlines():
        if disk_substr in line and 'part' not in line:
            return line
    return None


def main():
    if len(sys.argv) < 4:
        return
    leaderip = sys.argv[1]
    pool = sys.argv[2]
    myhost = sys.argv[3]

    initallphy(leaderip)
    info = getall(leaderip)

    pool_data = info['pools'].get(pool)
    if not pool_data:
        return

    cache_disks = []
    for raid_id in pool_data.get('raids', []):
        if raid_id.split('_')[0] == 'cache':
            cache_disks.extend(info['raids'].get(raid_id, {}).get('disks', []))

    if not cache_disks:
        print(f"fixcachelocality: pool {pool} has no cache vdev, nothing to do")
        return

    remote_cache_disks = [d for d in cache_disks if info['disks'].get(d, {}).get('host') != myhost]
    if not remote_cache_disks:
        print(f"fixcachelocality: pool {pool}'s cache is already local to {myhost}")
        return

    print(f"fixcachelocality: pool {pool}'s cache disk(s) {remote_cache_disks} are not local to {myhost}, relocating")

    local_spare = None
    for raid_data in info['raids'].values():
        if raid_data.get('status') == 'cache':
            for d in raid_data.get('disks', []):
                if info['disks'].get(d, {}).get('host') == myhost and d not in cache_disks:
                    local_spare = d
                    break
        if local_spare:
            break

    for d in remote_cache_disks:
        resolved = resolve_by_id(d)
        if resolved:
            print(f"fixcachelocality: removing remote cache disk {resolved} from {pool}")
            subprocess.run(['/sbin/zpool', 'remove', pool, resolved])
        else:
            print(f"fixcachelocality: could not resolve {d} locally to remove (expected - it lives on another host)")

    if local_spare:
        resolved = resolve_by_id(local_spare)
        if resolved:
            print(f"fixcachelocality: adding local spare {resolved} as new cache for {pool}")
            subprocess.run(['/sbin/zpool', 'add', '-f', pool, 'cache', resolved])
    else:
        print(f"fixcachelocality: no local spare cache disk available on {myhost}, pool {pool} now has no cache")


if __name__ == '__main__':
    main()
