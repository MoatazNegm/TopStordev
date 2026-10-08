#!/usr/bin/python3
# mockfapi.py -- sample-data replacement for fapi.py, for judging the web interface without a working storage backend.
# It serves the same /api/v1 routes on port 5001 with the same JSON shapes as the real handlers (shapes taken from
# fapi.py, allphysicalinfo.py, Hostsconfig.py, fapistats.py, getlogs.py), but every answer is fixed sample data:
# no etcd, no zpool, no LIO, no subprocess.  Any token is accepted; any user/password logs in.
# Switch on : touch /TopStordata/mockapi      (fapi.py hands over to this file at start-up when that file exists)
# Switch off: rm /TopStordata/mockapi         (the next start of fapi.py is the real API again)
# Changes made by the UI (create pool/volume/user, ...) are answered with 'Ok' and are NOT stored.
import time, json, copy
import flask
from flask import request, jsonify

app = flask.Flask(__name__)
NOW = int(time.time())
GB = 1.0

# ---------------------------------------------------------------- hosts, pools, raids, disks
HOSTS = {'node1': '10.11.11.201', 'node2': '10.11.11.202', 'node3': '10.11.11.203', 'node4': '10.11.11.204',
         'node5': '10.11.11.205'}
LEADER = 'node1'
# offline nodes: still partners (active) but not ready -> the UI shows them in the Status list only, not under Running Nodes
LOST = {'node6': '10.11.11.206', 'node7': '10.11.11.207'}


def disk(name, host, size, pool, raid, status='ONLINE', idx=0):
    return {'name': name, 'zname': 'sd' + chr(ord('b') + idx), 'actualdisk': 'sd' + chr(ord('b') + idx), 'changeop': status,
            'pool': pool, 'raid': raid, 'status': status, 'id': str(idx), 'host': host, 'size': size,
            'devname': 'sd' + chr(ord('b') + idx), 'silvering': 'no', 'replacingroup': ''}


def scsi(n):
    return 'scsi-36001405%024x' % (0xabc0000 + n * 7919)


DISKS, RAIDS, POOLS = {}, {}, {}
_n = 0


def mkpool(pool, host, raidtype, ndisks, dsize, cache=None, used=0.0):
    global _n
    raid = raidtype + '-0_' + pool
    names = []
    for i in range(ndisks):
        _n += 1
        d = scsi(_n)
        DISKS[d] = disk(d, host, dsize, pool, raid, idx=_n)
        names.append(d)
    RAIDS[raid] = {'name': raid, 'changeop': 'ONLINE', 'status': 'ONLINE', 'pool': pool, 'host': host, 'disks': names,
                   'silvering': 'no', 'missingdisks': [], 'rank': 3, 'raidtype': raidtype}
    raids = [raid]
    if cache:
        _n += 1
        c = scsi(_n)
        DISKS[c] = disk(c, host, cache, pool, 'cache_' + pool, idx=_n)
        RAIDS['cache_' + pool] = {'name': 'cache_' + pool, 'changeop': 'ONLINE', 'status': 'ONLINE', 'pool': pool,
                                  'host': host, 'disks': [c], 'silvering': 'no', 'missingdisks': []}
        raids.append('cache_' + pool)
    size = round(dsize * (ndisks - (1 if raidtype.startswith('raidz1') else 0)), 1)
    POOLS[pool] = {'name': pool, 'changeop': 'ONLINE', 'availtype': 'raidz', 'status': 'ONLINE', 'host': host,
                   'used': used, 'available': round(size - used, 1), 'alloc': used, 'size': size, 'empty': round(size - used, 1),
                   'dedup': '1.00x', 'compressratio': '1.37x', 'timestamp': str(NOW), 'silvering': 'no', 'raids': raids,
                   'volumes': [], 'Availability': 'None'}


mkpool('pdhcp1001', 'node1', 'raidz1', 4, 100.0, cache=20.0, used=118.4)
mkpool('pdhcp1002', 'node2', 'mirror', 2, 200.0, used=64.2)
mkpool('pdhcp1003', 'node3', 'raidz2', 6, 50.0, cache=10.0, used=282.0)
# free disks (not part of a pool): the UI offers them for new pools / spares
RAIDS['free'] = {'name': 'free', 'changeop': 'free', 'status': 'free', 'pool': 'pree', 'host': 'node1', 'disks': [],
                 'silvering': 'no', 'missingdisks': []}
for host, size in (('node1', 100.0), ('node1', 100.0), ('node2', 100.0), ('node2', 100.0), ('node3', 10.0), ('node3', 10.0)):
    _n += 1
    d = scsi(_n)
    DISKS[d] = disk(d, host, size, 'pree', 'free', status='free', idx=_n)
    RAIDS['free']['disks'].append(d)
POOLS['pree'] = {'name': 'pree', 'changeop': 'free', 'availtype': 'free', 'status': 'free', 'host': 'node1', 'used': 0, 'available': 0,
                 'alloc': 0, 'size': 0, 'empty': 0, 'dedup': '', 'compressratio': '', 'timestamp': str(NOW), 'silvering': 'no',
                 'raids': ['free'], 'volumes': [], 'Availability': 'None'}

free_by_size = {}
for _d in RAIDS['free']['disks']:
    free_by_size.setdefault(DISKS[_d]['size'], []).append(_d)
NEWRAID = {'single': free_by_size,
           'mirror': {100.0: [RAIDS['free']['disks'][0:2]]},
           'raid5': {100.0: RAIDS['free']['disks'][0:4]}}

# ---------------------------------------------------------------- volumes, snapshots
VOLS = {}


def vol(name, pool, prot, used, quota, groups='Everyone', ip='10.11.11.210', snaps=(), comp='lz4', dedup='on', ratio='1.41x'):
    host = POOLS[pool]['host']
    VOLS[name] = {'name': name, 'pool': pool, 'groups': groups, 'ipaddress': ip, 'Subnet': '24', 'prot': prot,
                  'fullname': name + '_' + pool, 'host': host, 'creation': 'Mon Jan 12 2026', 'time': '09:14',
                  'used': used, 'quota': quota, 'usedbysnapshots': round(used * 0.06 * 1024, 1), 'refcompressratio': ratio,
                  'compression': comp, 'dedup': dedup,
                  'available': round(quota - used, 1) if quota else round(POOLS[pool]['available'], 1), 'referenced': round(used * 1024, 1), 'statusmount': 'mounted', 'runtime': 'serviceok',
                  'type': 'WorkGroup', 'snapshots': list(snaps), 'snapperiod': []}
    POOLS[pool]['volumes'].append(name)


vol('finance', 'pdhcp1001', 'CIFS', 41.3, 100.0, groups='Finance', ip='10.11.11.211')
vol('engineering', 'pdhcp1001', 'CIFS', 52.8, 100.0, groups='Engineering', ip='10.11.11.212', snaps=['daily_0301'])
vol('alice', 'pdhcp1001', 'HOME', 6.2, 10.0, groups='alice', ip='10.11.11.51')
vol('bob', 'pdhcp1002', 'HOME', 18.7, 20.0, groups='bob', ip='10.11.11.52', comp='off', dedup='off', ratio='1.00x')
vol('carol', 'pdhcp1002', 'HOME', 1.1, 5.0, groups='carol', ip='10.11.11.53')
vol('backups', 'pdhcp1002', 'NFS', 33.9, 150.0, groups='10.11.11.0/24', ip='10.11.11.214', dedup='off', ratio='1.18x')
vol('archive', 'pdhcp1002', 'NFS', 41.0, 300.0, groups='10.11.11.0/24', ip='10.11.11.216', ratio='1.92x')
vol('scratch', 'pdhcp1003', 'CIFS', 190.0, 0, groups='Engineering', ip='10.11.11.217', comp='off', dedup='off', ratio='1.00x')
vol('payroll', 'pdhcp1001', 'CIFS_corp.local', 8.4, 40.0, groups='DOMAIN', ip='10.11.11.218')
VOLS['payroll']['type'] = 'DOMAIN'
vol('vmstore', 'pdhcp1003', 'ISCSI', 60.0, 60.0, ip='10.11.11.215')
VOLS['vmstore'].update({'portalport': '3260', 'initiators': 'iqn.1998-01.com.vmware:esx01', 'chapuser': 'vmuser', 'chappas': 'x'})
VOLS['vmstore']['referenced'] = 34200.0          # a LUN reserves its whole size; what was written to it is 'referenced' (MB)
vol('dbstore', 'pdhcp1001', 'ISCSI', 80.0, 80.0, ip='10.11.11.215')
VOLS['dbstore'].update({'portalport': '3260', 'initiators': 'iqn.1998-01.com.debian:db01,iqn.1998-01.com.debian:db02', 'chapuser': 'dbuser', 'chappas': 'x', 'referenced': 71800.0})

SNAPS = {'daily_0301': {'fullname': 'pdhcp1001/engineering@daily_0301', 'name': 'daily_0301', 'volume': 'engineering',
                        'pool': 'pdhcp1001', 'host': 'node1', 'creation': 'Sun Mar 01 2026', 'time': '02:00', 'used': 1.2,
                        'quota': 0, 'usedbysnapshots': 0, 'refcompressratio': '1.40x', 'prot': 'CIFS', 'referenced': 52.0,
                        'statusmount': 'mounted', 'snaptype': 'Hourly', 'partnerR': 'no', 'partnerS': 'no',
                        'date': '01-March-2026'},
         'manual_0305': {'fullname': 'pdhcp1002/backups@manual_0305', 'name': 'manual_0305', 'volume': 'backups',
                         'pool': 'pdhcp1002', 'host': 'node2', 'creation': 'Thu Mar 05 2026', 'time': '16:41', 'used': 0.4,
                         'quota': 0, 'usedbysnapshots': 0, 'refcompressratio': '1.30x', 'prot': 'NFS', 'referenced': 33.0,
                         'statusmount': 'mounted', 'snaptype': 'Once', 'partnerR': 'no', 'partnerS': 'no',
                         'date': '05-March-2026'}}
PERIODS = {'hr_eng': {'host': 'node1', 'pool': 'pdhcp1001', 'volume': 'engineering', 'periodtype': 'Hourly', 'id': 'hr_eng',
                      'receiver': 'local', 'keep': '24', 'sminute': '0', 'every': '1'}}

# ---------------------------------------------------------------- users, groups, partners
USERS = [('admin', 'NoHome', 'na'), ('alice', 'pdhcp1001', '10'), ('bob', 'pdhcp1002', '20'), ('carol', 'pdhcp1002', '5'),
         ('dave', 'NoHome', 'na')]
GROUPS = [['Everyone', '0', 'admin,alice,bob,carol,dave'], ['Finance', '1', 'alice,carol'], ['Engineering', '2', 'bob,dave']]
HOME_ADDRESSES = {'alice': '10.11.11.51', 'bob': '10.11.11.52', 'carol': '10.11.11.53'}
HOME_SUBNETS = {'alice': '24', 'bob': '16', 'carol': '24'}
PARTNERS = [{'alias': 'dr-site', 'ip': '10.20.30.40', 'type': 'sync', 'port': '2222'}]


def users_payload():
    members = {}
    for g in GROUPS:
        for u in g[2].split(','):
            members.setdefault(u, []).append(g[1])
    allusers = [{'name': n, 'id': i, 'pool': p, 'size': s, 'groups': members.get(n, ['NoGroup']),
                 'priv': 'CIFS/NFS/ISCSI/HOME/POOLS/USERS' if n == 'admin' else 'CIFS/HOME'} for i, (n, p, s) in enumerate(USERS)]
    # a user with a home folder cannot exist without a valid address: sample addresses for those
    for u in allusers:
        if u['pool'] != 'NoHome':
            u['HomeAddress'] = HOME_ADDRESSES.get(u['name'], '10.11.11.60')
            u['HomeSubnet'] = HOME_SUBNETS.get(u['name'], '24')
    nohome = [{'id': i, 'text': n} for i, n in enumerate(u[0] for u in USERS if u[1] == 'NoHome')]
    return {'allusers': allusers, 'allgroups': GROUPS, 'usersnohome': nohome}


# ---------------------------------------------------------------- logs / notifications
def logrows():
    rows = [('info', 'Lognsu0', 'node1', 'system', 'admin', 'User admin logged in.'),
            ('info', 'Posu0', 'node1', 'system', 'admin', 'Pool pdhcp1001 status changed to ONLINE.'),
            ('warning', 'Diwa1', 'node2', 'system', 'system', 'Pool pdhcp1002 is degraded.'),
            ('info', 'Disu6', 'node3', 'system', 'admin', 'Success attaching Disk sdh to group raidz2-0 in pool pdhcp1003.'),
            ('error', 'Lognfa0', 'node1', 'system', 'mallory', 'Failed logon for user mallory.'),
            ('info', 'Actsu1000', 'node1', 'system', 'system', 'Volumes info are synced.')]
    out = []
    for i, (imp, code, host, typ, user, msg) in enumerate(rows):
        t = time.gmtime(NOW - 3600 * (len(rows) - i))
        out.append({'importance': imp, 'msgcode': code, 'date': time.strftime('%m/%d/%Y', t), 'time': time.strftime('%H:%M:%S', t),
                    'host': host, 'type': typ, 'user': user, 'msgbody': msg})
    return out


def allinfo():
    return {'raids': RAIDS, 'pools': POOLS, 'disks': DISKS}


def hostrows():
    allh = {}
    for i, (h, ip) in enumerate(HOSTS.items()):
        allh[h] = {'isLeader': h == LEADER, 'ports': [['ports/' + h, 'eth0/eth1/eth2/eth3']], 'configured': 'yes',
                   'alias': '_1' if h == 'node5' else 'rack1-' + h, 'ipaddr': ip, 'ipaddrsubnet': '24', 'ntp': '10.11.11.1', 'tz': 'Europe/Berlin',
                   'gw': '10.11.11.1', 'dnsname': 'storage.example.local', 'dnssearch': 'example.local', 'cluster': '10.11.11.200',
                   'nmports': 'eth0', 'cmports': 'eth1', 'dports': 'eth2', 'iports': 'eth3'}
    return allh


def lst(items):
    return [{'name': h, 'ip': ip, 'id': i} for i, (h, ip) in enumerate(items)]


# ---------------------------------------------------------------- routes
def echo():
    d = request.args.to_dict()
    d['response'] = 'Ok'
    return jsonify(d)


R = {}


def route(path, fn):
    R[path] = fn


def vols_by_prot(prot):
    out = []
    for v in VOLS.values():
        if prot == 'all' or v['prot'] == prot or (prot == 'CIFS' and v['prot'].startswith('CIFS_')) or (prot == 'all' and v['prot'] in ('CIFS', 'HOME')):
            c = copy.deepcopy(v)
            gids = [g[1] for g in GROUPS if g[0] in str(v['groups']).split(',')] if prot in ('CIFS', 'NFS') else []
            c['groups'] = gids
            out.append(c)
    return out


def snapshots_payload():
    snaplist = {'Once': [], 'Minutely': [], 'Hourly': [], 'Weekly': []}
    for s in SNAPS.values():
        snaplist[s['snaptype']].append(s)
    per = {'Minutely': [], 'Hourly': [], 'Weekly': [], 'Trend': []}
    for p in PERIODS.values():
        per[p['periodtype']].append(p)
    return {'allsnaps': list(SNAPS.values()), 'Once': snaplist['Once'], 'Hourly': snaplist['Hourly'], 'Weekly': snaplist['Weekly'],
            'Minutely': snaplist['Minutely'], 'allperiods': list(PERIODS.values()), 'Minutelyperiod': per['Minutely'],
            'Hourlyperiod': per['Hourly'], 'Weeklyperiod': per['Weekly']}


def stats_payload():
    st = {'trends': {}}
    for key in ('used', 'quota', 'usedbysnapshots'):
        pairs = sorted(((v['name'], v['fullname'], v[key]) for v in VOLS.values()), key=lambda x: x[2], reverse=True)
        top, rest = pairs[:3], pairs[3:]
        st[key] = {'fulllabels': ['others'] + [p[1] for p in top], 'labels': ['others'] + [p[0] for p in top],
                   'stats': [round(sum(p[2] for p in rest), 2)] + [p[2] for p in top]}
    for v in VOLS.values():
        st['trends'][v['fullname']] = '/'.join(str(round(v['used'] * (0.8 + i * 0.04), 1)) for i in range(6))
    return st


# Sample notifications for the toasts: the real API puts the severity into 'type' (info|warning|error) and the user
# (admin, system, ...) into 'user'.  One sample per 7 s poll, round robin, so every look of the toast is seen.
NOTIFS = [('info', 'Actsu1000', 'node1', 'system', 'Volumes info are synced.'),
          ('info', 'Posu0', 'node2', 'admin', 'Pool pdhcp1001 status changed to ONLINE.'),
          ('warning', 'Diwa1', 'node3', 'system', 'Pool pdhcp1002 is degraded, one disk is missing.'),
          ('info', 'Disu6', 'node4', 'admin', 'Success attaching Disk sdh to group raidz2-0 in pool pdhcp1003.'),
          ('error', 'Lognfa0', 'node1', 'mallory', 'Failed logon for user mallory.'),
          ('warning', 'Volwa3', 'node5', 'system', 'Volume finance_pdhc has used 91 percent of its quota.'),
          ('error', 'DGfa25', 'node2', 'admin', 'Pool pdhcp1002 was not deleted, it still holds volumes.'),
          ('warning', 'Poolcap90', 'node3', 'system', 'Pool pdhcp1003 is above 90 percent of its real capacity, free space left 18.0G.'),
          ('info', 'Lognsu0', 'node1', 'admin', 'User admin logged in.')]
# cluster state shown by the sign next to the bell: cycles every 5 minutes (minutes 0-2 in sync, 3 not in sync,
# 4 single node: only the 'active' list of hosts/allinfo shrinks to one node).  Force one with the file
# /TopStordata/mockphase containing: insync | notinsync | single   (no file = the cycle).
def phase():
    try:
        with open('/TopStordata/mockphase') as f:
            w = f.read().strip()
        if w in ('insync', 'notinsync', 'single'):
            return w
    except OSError:
        pass
    m = int(time.time() // 60) % 5
    return 'notinsync' if m == 3 else 'single' if m == 4 else 'insync'


def notification():
    slot = int(time.time() // 7)
    imp, code, host, user, msg = NOTIFS[slot % len(NOTIFS)]
    return {'isinsync': 'no' if phase() == 'notinsync' else 'yes', 'importance': imp, 'msgcode': code,
            'date': time.strftime('%m/%d/%Y'), 'time': time.strftime('%H:%M:%S', time.localtime(slot * 7)), 'host': host, 'type': imp, 'user': user,
            'msgbody': msg, 'requests': {}, 'response': 'Ok'}


def activehosts():
    return lst([('node1', HOSTS['node1'])] if phase() == 'single' else list(HOSTS.items()) + list(LOST.items()))


route('/api/v1/login', lambda: jsonify({'token': 'mocktoken' + str(NOW)}))
route('/api/v1/login/test', lambda: jsonify({'response': 'admin'}))
route('/api/v1/login/renewtoken', echo)
route('/api/v1/logout', echo)
route('/api/v1/info/summary', lambda: jsonify({'users': len(USERS), 'groups': len(GROUPS), 'pools': len(POOLS) - 1,
                                               'volumes': {'cifs': 2, 'nfs': 1, 'iscsi': 1}}))
route('/api/v1/info/performance', lambda: jsonify([{'host': h, 'cpu': str(12 + 9 * i)} for i, h in enumerate(HOSTS)]))
route('/api/v1/telemetry/heartbeat', lambda: jsonify({'status': 'boost_active'}))
route('/api/v1/info/notification', lambda: jsonify(notification()))
route('/api/v1/info/logs', lambda: jsonify({'alllogs': logrows()}))
route('/api/v1/info/onedaylog', lambda: jsonify({'failedlogon': ['Lognfa0 error system mallory'], 'info': ['Lognsu0 info system admin'],
                                                 'warning': ['Diwa1 warning system'], 'error': ['Lognfa0 error system mallory']}))
route('/api/v1/info/commandlog', lambda: jsonify({'response': 'Ok', 'commands': [
    {'user': 'admin', 'endpoint': '/api/v1/pools/newpool', 'method': 'POST', 'time': NOW - 600},
    {'user': 'admin', 'endpoint': '/api/v1/volumes/create', 'method': 'POST', 'time': NOW - 300}]}))
route('/api/v1/info/cversion', lambda: jsonify({'response': 'Ok', 'cversion': 'QSD5.233'}))
route('/api/v1/software/versions', lambda: jsonify({'versions': [{'id': 1, 'text': 'QSD5.231'}, {'id': 2, 'text': 'QSD5.232'},
                                                                  {'id': 3, 'text': 'QSD5.233'}], 'current': 'QSD5.233',
                                                    'response': 'admin'}))
route('/api/v1/software/setversion', echo)
route('/api/v1/software/apply', lambda: jsonify({'versions': [{'id': 3, 'text': 'QSD5.233'}], 'current': 'QSD5.233', 'response': 'admin'}))
route('/api/v1/software/update', lambda: jsonify({'data': 'sample: nothing is downloaded'}))
route('/api/v1/software/localFileUpdate', lambda: jsonify({'data': 'success'}))
route('/api/v1/hosts/allinfo', lambda: jsonify({'all': hostrows(), 'active': activehosts(),
                                                'ready': lst(HOSTS.items()), 'possible': lst([('node8', '10.11.11.208')]),
                                                'lost': lst(LOST.items())}))
route('/api/v1/hosts/syncnow', echo)
route('/api/v1/hosts/discover', echo)
route('/api/v1/hosts/config', echo)
route('/api/v1/hosts/joincluster', echo)
route('/api/v1/hosts/evacuate', echo)
route('/api/v1/hosts/getConfig', lambda: ('# sample node configuration\nhostname=node1\ncluster=10.11.11.200\n', 200,
                                          {'Content-Type': 'text/plain'}))
route('/api/v1/hosts/getAllConfig', lambda: ('# sample configuration of all nodes\n', 200, {'Content-Type': 'text/plain'}))
route('/api/v1/pools/dgsinfo', lambda: jsonify(dict(allinfo(), newraid=NEWRAID)))
route('/api/v1/pools/poolsinfo', lambda: jsonify({'results': [{'id': i, 'owner': p['host'], 'text': n} for i, (n, p) in
                                                              enumerate(x for x in POOLS.items() if x[0] != 'pree')] +
                                                             [{'id': len(POOLS) - 1, 'text': '-------'}]}))
route('/api/v1/volumes/poolsinfo', lambda: jsonify({'results': [{'id': i, 'owner': p['host'], 'text': n} for i, (n, p) in
                                                                enumerate(x for x in POOLS.items() if x[0] != 'pree')]}))
for _p in ('delpool', 'addtopool', 'cachespares', 'delcachespares', 'newpool', 'updatecache', 'actionOnDisk'):
    route('/api/v1/pools/' + _p, echo)
route('/api/v1/volumes/stats', lambda: jsonify(stats_payload()))
route('/api/v1/volumes/volumelist', lambda: jsonify([{'id': i, 'text': v['name'], 'fullname': v['fullname'], 'pool': v['pool']}
                                                     for i, v in enumerate(VOLS.values())]))
route('/api/v1/tenants/tenantinfo', lambda: jsonify({'results': [{'id': 0, 'pool': 'pdhcp1002', 'text': 'backups'},
                                                                 {'id': 1, 'text': 'Cluster'}]}))
route('/api/v1/volumes/connections', lambda: jsonify({'connections': [
    {'volume': 'finance', 'user': 'alice', 'device': '10.11.11.57'}, {'volume': 'engineering', 'user': 'bob', 'device': '10.11.11.58'},
    {'volume': 'backups', 'user': 'root', 'device': '10.11.11.90'}], 'response': 'admin'}))
route('/api/v1/volumes/snapshots/snapshotsinfo', lambda: jsonify(snapshots_payload()))
for _p, _prot in (('CIFS', 'CIFS'), ('ISCSI', 'ISCSI'), ('NFS', 'NFS'), ('HOME', 'HOME')):
    route('/api/v1/volumes/%s/volumesinfo' % _p, (lambda pr: lambda: jsonify({'allvolumes': vols_by_prot(pr)}))(_prot))
route('/api/v1/volumes/volumesinfo', lambda: jsonify({'allvolumes': vols_by_prot('all')}))
for _p in ('snapshots/create', 'snapshots/snaprollback', 'snapshots/perioddelete', 'snapshots/snapshotdel', 'create', 'config',
           'volumeactive', 'volumedel'):
    route('/api/v1/volumes/' + _p, echo)
route('/api/v1/volumes/grouplist', lambda: jsonify({'results': [{'text': g[0], 'id': g[1], 'users': [
    str(i) for i, u in enumerate(USERS) if u[0] in g[2].split(',')]} for g in GROUPS]}))
route('/api/v1/groups/grouplist', lambda: jsonify({'allgroups': [{'name': g[0], 'id': g[1], 'users': [
    i for i, u in enumerate(USERS) if u[0] in g[2].split(',')]} for g in GROUPS]}))
route('/api/v1/groups/userlist', lambda: jsonify({'results': [{'id': i, 'text': u[0]} for i, u in enumerate(USERS)]}))
route('/api/v1/users/grouplist', lambda: jsonify({'results': [{'id': g[1], 'text': g[0]} for g in GROUPS], 'response': 'admin'}))
route('/api/v1/users/userlist', lambda: jsonify(users_payload()))
route('/api/v1/users/userauths', lambda: jsonify({'auths': 'CIFS/NFS/ISCSI/HOME/POOLS/USERS', 'response': 'admin'}))
route('/api/v1/users/usersauth', echo)
route('/api/v1/partners/partnerlist', lambda: jsonify({'allpartners': PARTNERS}))
for _p in ('/api/v1/groups/groupchange', '/api/v1/groups/groupdel', '/api/v1/groups/UnixAddgroup', '/api/v1/replication/addpartner',
           '/api/v1/partners/partnerdel', '/api/v1/partners/AddPartner', '/api/v1/users/userchange', '/api/v1/users/userdel',
           '/api/v1/users/UnixAddUser', '/api/v1/users/uploadUsers', '/api/v1/user/changepass', '/api/v1/tenant/adduser'):
    route(_p, echo)
route('/api/v1/query', lambda: jsonify({'status': 'success', 'data': {'resultType': 'vector', 'result': []}}))


def make(path, fn):
    def view():
        return fn()
    view.__name__ = 'mock_' + path.replace('/', '_')
    app.add_url_rule(path, view_func=view, methods=['GET', 'POST'])


for _path, _fn in R.items():
    make(_path, _fn)


@app.route('/', methods=['GET'])
def home():
    return '<h1>TopStor sample API</h1><p>mockfapi.py: every answer is fixed sample data.</p>'


@app.errorhandler(404)
def notfound(e):
    # a route the UI calls that is not listed above: answer something harmless instead of a 404
    if request.path.startswith('/api/v1/'):
        return jsonify({'response': 'Ok', 'sample': True, 'path': request.path})
    return 'not found', 404


@app.after_request
def cors(resp):
    resp.headers['Access-Control-Allow-Origin'] = '*'
    return resp


def run():
    print('mockfapi: serving sample data on :5001 (%d routes)' % len(R))
    app.run(host='0.0.0.0', port=5001)


if __name__ == '__main__':
    run()
