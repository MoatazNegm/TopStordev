#!/usr/bin/env python3
import sys
import json
import subprocess
from time import time as timestamp
from etcdget import etcdget as get
from etcdput import etcdput as put
from etcddel import etcddel as dels


def _normalize_current_json(current_json):
    if not current_json or current_json == 'None':
        return []

    val = current_json
    
    if isinstance(val, tuple) and len(val) > 1:
        val = val[1]

    for _ in range(3):
        try:
            parsed = json.loads(val)
        except (TypeError, ValueError):
            break
        else:
            val = parsed
            if isinstance(val, list):
                return [str(x) for x in val]

    if isinstance(val, list):
        return [str(x) for x in val]

    return [str(val)] if val else []


def _leadername(leader_ip):
    try:
        res = get(leader_ip, 'leader')
        name = res[0] if isinstance(res, list) and res else res
        name = str(name).replace('\n', '').strip()
        return '' if name in ('', '_1', '-1', 'None') else name
    except Exception:
        return ''


def post_sync(leader_ip, action, disks):
    """QSD5.351: whole-etcd sync 'cachespares' (pace/checksyncs.py wholeetcd): every follower copies the leader's
    list into its own etcd, so a node that takes over the leadership still knows the spare cache disks
    (QC 631: the new leader's list was empty, fixcachelocality rule 1 found no spare). Same pattern as
    fapi.apikey_sync: drop the older cachespares requests, post the request and mark the leader done."""
    op = 'Del' if action == 'del' else 'Add'
    tag = '::'.join(str(d).replace('_', ':::').replace('/', ':::') for d in disks)[:200] or 'list'
    stampv = 'cachespares_' + str(timestamp())
    req = 'sync/cachespares/' + op + '_' + tag + '/request'
    dels(leader_ip, 'sync/cachespares', 'cachespares_')
    put(leader_ip, req, stampv)
    leader = _leadername(leader_ip)
    if leader:
        put(leader_ip, req + '/' + leader, stampv)
    return req, stampv


def main():
    if len(sys.argv) < 4:
        sys.exit(1)

    action = sys.argv[1]
    leader_ip = sys.argv[2]
    disks_arg = sys.argv[3:]
    etcd_key = "cachespares"

    res = get(leader_ip, etcd_key, "--prefix")
    
    current_json = None
    if isinstance(res, tuple) and len(res) >= 2:
        current_json = res[1]
    elif isinstance(res, list) and len(res) > 0 and isinstance(res[0], tuple):
        current_json = res[0][1]
    else:
        current_json = res

    try:
        current_list = _normalize_current_json(current_json)
    except Exception:
        current_list = []

    new_list = list(current_list)

    if action == "del":
        new_list = [d for d in current_list if d not in disks_arg]
    elif action == "add":
        for d in disks_arg:
            d = str(d)
            if d not in new_list:
                new_list.append(d)

    if set(new_list) != set(current_list):
        put(leader_ip, etcd_key, json.dumps(new_list))
        post_sync(leader_ip, action, disks_arg)
        subprocess.run(["/pace/putzpool.py"])


if __name__ == "__main__":
    main()
