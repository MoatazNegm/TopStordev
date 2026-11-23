#!/usr/bin/python3
import time as _startclock; _FAPI_T0 = _startclock.time()      # for the start-up log at the bottom: when the interpreter started
import time
# sample-data mode (pzfs UI work): /TopStordata/mockapi exists -> serve mockfapi.py instead of the real API (rm it to switch off)
import os as _os
if _os.path.exists('/TopStordata/mockapi'):
    import mockfapi; mockfapi.run(); raise SystemExit
import flask, os, Evacuate, subprocess, Joincluster, sys, re
from getversions import getversions
from functools import wraps
from copy import deepcopy
from flask import request, jsonify, render_template, redirect, url_for, g, send_file
import re, ipaddress, traceback
import Hostsconfig
from Hostconfig import config
from allphysicalinfo import getall, initallphy
from uservalid import check_new_user_coded, logname, check_group_name, check_password_target, check_new_group_name, CODE_GROUPNAME
from volvalid import check_volname_coded, logname as vollogname
from UnixChkUser import setlogin
import sqlite3
from etcdget2 import etcdgetjson
from etcdgetlocalpy import etcdget  as get
from etcddellocal import etcddel  as dels 
from etcdput import etcdput as put
from sendhost import sendhost
from secretmask import secret_values, mask_text, masked, is_secret_key, MASK, phrase_encrypt, phrase_decrypt, mask_query
import logging
from secretmask import SECRET_KEYS as MASK_KEYS     # QSD5.344: own name, the request guard below has its own SECRET_KEYS
from socket import gethostname as hostname
from getlogs import getlogs, onedaylog
from fapistats import allvolstats, cpuperf
from datetime import datetime
from getallraids import newraids
from fastselect import selectdisks
from raid10 import selectraid10
from raid5060 import selectraid50, selectraid60, raidwidthof
from secrets import token_hex
from time import time as timestamp
import logmsg
from collectNodeConfig import getConfig, downloadConfig
import zipfile
from time import sleep
import socket
import json
import threading

_cmdctx = threading.local()
_orig_popen_init = subprocess.Popen.__init__

def _cmdaudit_popen_init(self, args, *a, **kw):
 try:
  cmds = getattr(_cmdctx, 'commands', None)
  if cmds is not None:
   cmds.append(args if isinstance(args, str) else ' '.join(str(x) for x in args))
 except:
  pass
 return _orig_popen_init(self, args, *a, **kw)

subprocess.Popen.__init__ = _cmdaudit_popen_init

getalltimestamp = 0
os.environ['ETCDCTL_API'] = '3'
loggedusers = dict() 
alldsks = []
allpools = 0
allgroups = []
allvolumes = []
allusers = []
readyhosts = []
activehosts = []
losthosts = []
possiblehosts = []
pooldict = dict()
app = flask.Flask(__name__)
# QSD5.321: no Flask debug mode.  With DEBUG True app.run() served the interactive Werkzeug debugger (tracebacks with source
# and local values, a PIN-protected console = remote code execution as root) on port 5001 of every interface for any
# unhandled exception (tests 601, 625).  Unhandled exceptions now answer the generic JSON 500 of fapi_unhandled() below.
app.config["DEBUG"] = False
app.config["PROPAGATE_EXCEPTIONS"] = False

class _AccessLogMask(logging.Filter):
 # QSD5.345 (QX-233 step 4): the werkzeug access log line holds the request line with its query string -- the login token
 # or the API key (qsk.<name>.<secret>) of every call and the password of a form sent by GET.  The prints of the routes
 # were masked in QSD5.344 (logsafe), this line was not.  The secret parameter values are written as ****.
 def filter(self, record):
  try:
   msg = record.getMessage()
   safe = mask_query(msg)
   if safe != msg:
    record.msg = safe
    record.args = ()
  except Exception:
   pass
  return True

logging.getLogger('werkzeug').addFilter(_AccessLogMask())
logcatalog = ''
with open('/TopStor/msgsglobal.txt') as f:
 logcatalog = f.read().split('\n')
logdict = dict()
for log in logcatalog:
 msgcode= log.split(':')[0]
 logdict[msgcode] = log.replace(msgcode+':','').split(' ')
allinfo = 0

from werkzeug.exceptions import HTTPException as _HTTPException
@app.errorhandler(Exception)
def fapi_unhandled(e):
 # HTTP errors (404, 405, 400 ...) keep Flask's own answer; any other exception is logged on the node (stderr of fapi,
 # with the traceback) and the client gets only a generic JSON 500, never a traceback or the debugger
 if isinstance(e, _HTTPException):
  return e
 try:
  print('fapi: unhandled exception on '+str(request.method)+' '+str(request.path), file=sys.stderr)
  traceback.print_exc()
 except Exception:
  pass
 return jsonify({'response': 'error', 'message': 'internal error'}), 500


def is_valid_ip(ip):
    try:
        ipaddress.ip_address(ip)
        return 0 
    except ValueError:
        return 10 


def is_unique_ip(ip, vtype='NZ#@A', partnerskip=()):
        global leaderip
        if not ip or not str(ip).strip():
            return 0
        allvols = get('vol', '--prefix')
        allvols = [x for x in allvols if vtype not in str(x)]
        allvols = str(allvols)
        allnodes= get('Active','--prefix')
        allnodes = str(allnodes)
        allpartners= get('Partner','--prefix')
        # QSD5.345: partnerskip = names '<alias>_<type>' (lower case, as Partner/<name> is stored) whose address may be
        # shared: AddPartner passes the OTHER type of the same alias, so one cluster can be both the Sender and the
        # Receiver partner (same address); every other use of the address stays refused
        if partnerskip:
            allpartners = [x for x in allpartners if not (isinstance(x, (list, tuple)) and len(x) > 1
                           and str(x[0]).startswith('Partner/') and str(x[0]).split('/',1)[1].lower() in partnerskip)]
        allpartners = str(allpartners)
        allips = allvols+'/'+leaderip+'/'+allnodes+'/'+allpartners
        ip_pattern = rf'\b{re.escape(ip)}\b' 
        if bool(re.search(ip_pattern,allips)):
                    print("Invalid IP")
                    return 100 
        print("Valid IP")
        return 0 

# Every user is a member of the group Everyone, always: the front end neither shows nor edits it, so the group lists
# it sends never contain it.  Every command that sets the groups of a user goes through this function.
EVERYONE = 'Everyone'
def with_everyone(groupstr):
        names = [g for g in str(groupstr).split(',') if g and g != 'NoGroup']
        if EVERYONE not in names:
                names.append(EVERYONE)
        return ','.join(names)

# The groups of a user as a client sends them: a comma separated list of group ids (the position in getgroups(), what
# users/grouplist answers as 'id') or of group names.  A value of digits only is an id; anything else must be the exact
# name of a group.  Returns (groupstr, bad): groupstr is 'NoGroup' or the names joined by ',', bad lists the values that
# are neither, so the caller refuses them instead of failing on them (test 609 step 2: names gave an HTTP 500).
def resolve_groups(grps, allgroups):
        names, bad = [], []
        for grp in str(grps or '').split(','):
                grp = grp.strip()
                if not grp or grp == 'NoGroup':
                        continue
                if grp.isdigit() and int(grp) < len(allgroups):
                        name = allgroups[int(grp)][0]
                else:
                        name = next((g[0] for g in allgroups if g[0] == grp), None)
                if name is None:
                        bad.append(grp)
                elif name not in names:
                        names.append(name)
        return (','.join(names) if names else 'NoGroup'), bad

# Everyone as the group of a share means all users (every user is a member of it): when it is among the groups the
# others add nothing, so the share gets Everyone alone.
def only_everyone(groups):
        names = [g for g in str(groups).split(',') if g]
        return EVERYONE if EVERYONE in names else groups

# Which volumes may share the IP address a new or changed volume asks for.  is_unique_ip() leaves out the volumes whose etcd
# key holds this text: a CIFS share may share an address only with the CIFS shares of the same context (the workgroup shares
# volumes/CIFS/..., the shares of a domain volumes/CIFS_<domain>/...: one share container serves one workgroup or one domain),
# homes with homes, iSCSI with iSCSI; NFS shares share no address at all.
def ip_context(kind, domain=''):
        if kind == 'CIFS':
                return 'volumes/CIFS/'
        if kind == 'CIFSdom':
                return 'volumes/CIFS_'+str(domain)+'/'
        if kind.startswith('CIFS_'):
                return 'volumes/'+kind+'/'
        if 'NFS' in kind:
                return 'ANYthing'
        return kind

def has_privilege(priv, user):
        # same rule as /TopStor/privthis.sh: admin and system may do everything, any other user needs the privilege flag '<priv>-true' in
        # usersinfo/<user>.  Read from etcd here: this code runs inside the 'flask' container, where privthis.sh cannot work (/bin/sh is dash
        # and there is no docker CLI), so shelling out answered 'false' for every non-admin user, also for one that HAS the privilege.
        # QSD5.343: a name without usersinfo/<name> may be an API key: same rule as privthis.sh / privthis.py (an active write key
        # has every privilege except APIKEY_DENIED_PRIVS, a read key none).
        if user in ('admin', 'system'):
                return True
        try:
                info = str(get('usersinfo/'+str(user))[0])
                if info in ('_1', '-1', '', 'None'):
                        if priv in APIKEY_DENIED_PRIVS:
                                return False
                        rec = apikeys_all().get(str(user))
                        return bool(rec) and rec.get('access') == 'write' and rec.get('status') == 'active'
                return re.search(r'(^|/)'+re.escape(str(priv))+r'-true(/|$)', info) is not None
        except Exception:
                return False

def upload_name(raw):
        # QSD5.352 r4 (validator N2): the name an uploaded file is saved under in /TopStordata.  Werkzeug passes the client's file
        # name raw, and os.path.join('/TopStordata', '/TopStor/x.sh') or '../../TopStor/x.sh' leaves /TopStordata.  Keep the base
        # name only (also after a Windows '\\' path), without blanks as before; None (refused) when nothing usable is left.
        name = os.path.basename(str(raw or '').replace('\\', '/')).replace(' ', '')
        if name in ('', '.', '..') or '\x00' in name:
                return None
        return name

UPLOAD_DIR = '/TopStordata/uploads'

def save_upload(uploaded_file, name):
        # QSD5.352 r5 (validator N3): uploads (users/uploadUsers, software/localFileUpdate) went into /TopStordata itself, so an upload
        # named cmdaudit.log, partners.txt, bondconfig, hostname, smb.<ip>, a pool name (zpool cache file) ... replaced a file the node
        # uses.  They are saved in their own folder /TopStordata/uploads (created when missing).  A folder or target that is a symlink
        # or not a plain directory / regular file is refused, and the file is opened with O_NOFOLLOW (no symlink race).
        # Returns the full path, or None (refused).
        try:
                if os.path.islink(UPLOAD_DIR) or (os.path.lexists(UPLOAD_DIR) and not os.path.isdir(UPLOAD_DIR)):
                        return None
                os.makedirs(UPLOAD_DIR, mode=0o700, exist_ok=True)
                path = os.path.join(UPLOAD_DIR, name)
                if os.path.islink(path) or (os.path.lexists(path) and not os.path.isfile(path)):
                        return None
                fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
                with os.fdopen(fd, 'wb') as f:
                        uploaded_file.save(f)
                return path
        except OSError:
                return None

def name_in_volumes(name, volumes_text):
        # QSD5.352 (QC 709): a volume is stored as <name>_<id> (volumes/<type>/<host>/<pool>/<name>_<id>); '\b' does not split
        # 'q110v_123' ('_' is a word character), so a user or group could take a volume's name and only the scripts refused
        # it later (Unlin1021uv / Unlin1021gv).  Same pattern as UnixAddUser / UnixAddGroup.
        pattern = r'(^|[^A-Za-z0-9_])'+re.escape(str(name))+r'(_[0-9]+)?([^A-Za-z0-9_]|$)'
        return re.search(pattern, volumes_text) is not None

def _etcdkeys(prefix):
        # the keys of a --prefix read; etcdget answers [(key, value), ...] or ['_1'] when there is nothing
        try:
                return [str(x[0]) for x in get(prefix, '--prefix') if isinstance(x, (tuple, list)) and len(x) > 0]
        except Exception:
                return []

def volshortname(volkey):
        # volumes/<type>/<host>/<pool>/<name>_<id> -> <name> (a replica keeps its <name>_<id>: the same short name)
        return re.sub(r'_[0-9]+$', '', str(volkey).rstrip('/').split('/')[-1])

def is_unique_name(name, home=False, vols=True):
        global leaderip, allinfo
        # merge M+A: 1000 when a user, a group or a volume has EXACTLY this name.
        # A (test 614 and others): exact keys, not a \b regex over the whole etcd dump ('_' is a word character, so the volume
        # q022c (.../q022c_268804297) never matched, while any word of any value did).  vols=False (A's volumes/create): no
        # volume check (a second volume of the same short name is refused by its script, Unlin1021vv; a replica <name>_repli is
        # not stopped by its own source).  A home (volumes/HOME*/.../<user>_<id>) belongs to its user and is not counted.
        # M (QSD5.352 r9 D4, r9b V4): home=True (volumes/create type HOME, named after its user): the user of exactly this name
        # does not count, a group of that name or a volume (an existing home <name>_<id> included) still does; the datasets
        # of allinfo count as volumes too (a dataset whose record is missing, QC 709).
        name = str(name)
        taken = False
        for key in _etcdkeys('users'):
                part = key.split('/')
                if len(part) >= 2 and part[1] == name and part[0] in ('usersinfo', 'usershash', 'usersigroup'):
                        if home and part[0] != 'usersigroup':
                                continue
                        taken = True
                        break
        if not taken and vols:
                names = [ volshortname(key) for key in _etcdkeys('volumes/') if home or not key.startswith('volumes/HOME') ]
                try:
                        getalltime()
                        names += [ volshortname(v) for v in allinfo.get('volumes', {}) ]
                except Exception as e:
                        print('is_unique_name: volumes', e)
                taken = name in names
        if taken:
                    print("Invalid Name")
                    return 1000 
        print("Valid Name")
        return 0 

# volumes/create type=HOME: a home is named after its user, so the name must be an EXISTING user without a home (the opposite
# of is_unique_name, which refused every home: test 655 QX-056 step 2).  Returns (error, message, pool), (None, None, None)
# when the home may be made.  'hashome' when usersinfo/<user> names a pool (not NoHome) or a volumes/HOME*/.../<user>_<id>
# exists (the check of VolumeCreateHOME, Unlin1028, answered here at once).
def home_user_check(name):
        name = str(name)
        info = None
        try:
                for x in get('usersinfo/'+name, '--prefix'):
                        if isinstance(x, (tuple, list)) and len(x) > 1 and str(x[0]) == 'usersinfo/'+name:
                                info = str(x[1])
                                break
        except Exception:
                info = None
        if info is None:
                return 'nouser', 'no such user: '+name, ''
        part = info.split('/')
        pool = part[1] if len(part) > 1 else ''
        if pool and pool != 'NoHome':
                return 'hashome', 'the user '+name+' already has a home folder in pool '+pool+': delete it first', pool
        for key in _etcdkeys('volumes/HOME'):
                if volshortname(key) == name:
                        part = key.split('/')
                        pool = part[3] if len(part) > 4 else ''
                        return 'hashome', 'the user '+name+' already has a home folder in pool '+pool+': delete it first', pool
        return None, None, None



def getalltime(renew='no'):
 global allinfo,alldsks, getalltimestamp, leaderip
 #if (getalltimestamp+30) < timestamp() or renew == 'yes':
 if (getalltimestamp+1) < timestamp() or renew == 'yes':
  alldsks = deepcopy(get('host','current'))
  allinfo = deepcopy(getall(leaderip, alldsks))
  getalltimestamp = timestamp()
 return

# ---------------------------------------------------------------------------------------------------------------------------
# API keys (QSD5.308): named credentials for scripts and applications.  A key is NOT a system user (no unix user, group, home,
# no usersinfo/usersigroup entry, no console login); its name is the user name of the audit log and of the notifications.
# The key  qsk.<name>.<secret>  is passed as 'token'.  etcd (leader, synced to every node as the whole-etcd sync 'apikeys'):
#    apikeys/<name> = <access>/<status>/<created>/<createdby>/<lastused>/<revoked>/<salt>/<hash>     ('-' = empty)
# only a salted HMAC of the secret is stored; the key itself is shown once, on create/regenerate.
import hmac as _hmac, hashlib as _hashlib, secrets as _secrets
from etcdgetpy import etcdget as _getleader
from etcddel import etcddel as _delleader

APIKEY_NAME_RE = re.compile(r'^[A-Za-z][A-Za-z0-9_-]{2,31}$')
APIKEY_FAIL_MAX = 10                 # failed key attempts from one source IP ...
APIKEY_FAIL_WINDOW = 300             # ... within this many seconds lock that IP out ...
APIKEY_LOCKOUT = 300                 # ... for this many seconds
APIKEY_LASTUSED_EVERY = 60           # lastused is written at most once a minute per key
_apikey_fails = {}                   # ip -> [timestamps of failures]
_apikey_locked = {}                  # ip -> locked until
_apikey_lastwrite = {}               # name -> time of the last lastused write

# the key may never call these (key management, users, groups, privileges, joining, software, login session)
APIKEY_NEVER = ('/api/v1/users/uploadUsers', '/api/v1/groups/groupchange', '/api/v1/users/userchange', '/api/v1/users/userdel',
                '/api/v1/groups/groupdel', '/api/v1/groups/UnixAddgroup', '/api/v1/users/UnixAddUser', '/api/v1/users/usersauth',
                '/api/v1/user/changepass', '/api/v1/tenant/adduser', '/api/v1/hosts/joincluster', '/api/v1/software/update',
                '/api/v1/software/localFileUpdate', '/api/v1/software/setversion', '/api/v1/software/apply',
                '/api/v1/login/renewtoken', '/api/v1/logout', '/api/v1/replication/addpartner',
                '/api/v1/users/userhomechange')   # QSD5.352 r2 (supervisor ruling): like its sibling user routes
# QSD5.343: privileges an API key never has, also when the executor checks them (privthis.sh / privthis.py keep the same list):
# users and groups (Box_Users, Box_users), privileges (UserPrivilegesch), software (Uploadch), node config / join (Error)
APIKEY_DENIED_PRIVS = ('UserPrivilegesch', 'Box_Users', 'Box_users', 'Uploadch', 'Error')
# calls that change nothing: a 'read' key may call only these (every other call is a change call)
APIKEY_READ = ('/api/v1/volumes/connections', '/api/v1/software/versions', '/api/v1/hosts/allinfo', '/api/v1/pools/dgsinfo',
               '/api/v1/volumes/stats', '/api/v1/volumes/volumelist', '/api/v1/tenants/tenantinfo', '/api/v1/volumes/poolsinfo',
               '/api/v1/volumes/snapshots/snapshotsinfo', '/api/v1/volumes/CIFS/volumesinfo', '/api/v1/volumes/ISCSI/volumesinfo',
               '/api/v1/volumes/NFS/volumesinfo', '/api/v1/volumes/HOME/volumesinfo', '/api/v1/volumes/S3/volumesinfo', '/api/v1/volumes/volumesinfo',
               '/api/v1/pools/poolsinfo', '/api/v1/info/onedaylog', '/api/v1/info/logs', '/api/v1/info/commandlog',
               '/api/v1/info/cversion', '/api/v1/info/notification', '/api/v1/info/summary', '/api/v1/volumes/grouplist',
               '/api/v1/groups/grouplist', '/api/v1/users/userauths', '/api/v1/partners/partnerlist',
               '/api/v1/partners/freeport', '/api/v1/users/userlist', '/api/v1/groups/userlist', '/api/v1/users/grouplist',
               '/api/v1/hosts/getConfig', '/api/v1/hosts/getAllConfig', '/api/v1/login/test')

def _apikey_hash(salt, secret):
 return _hmac.new(salt.encode(), secret.encode(), _hashlib.sha256).hexdigest()

def _apikey_record(raw):
 # etcd value -> dict (None when it is not a key record)
 f = str(raw).split('/')
 if len(f) != 8:
  return None
 return {'access': f[0], 'status': f[1], 'created': f[2], 'createdby': f[3], 'lastused': f[4], 'revoked': f[5], 'salt': f[6], 'hash': f[7]}

def _apikey_value(rec):
 return '/'.join(str(rec[k]) or '-' for k in ('access','status','created','createdby','lastused','revoked','salt','hash'))

def apikeys_all():
 # name -> record, read from the leader's etcd (a revoke is effective at once, on whichever node the call arrives)
 keys = {}
 try:
  rows = _getleader(leaderip, 'apikeys/', '--prefix')
 except Exception:
  rows = get('apikeys/', '--prefix')
 for row in rows:
  if not isinstance(row, (tuple, list)) or len(row) < 2:
   continue
  rec = _apikey_record(row[1])
  if rec:
   keys[str(row[0]).split('/', 1)[1]] = rec
 return keys

def apikey_sync(name):
 # whole-etcd sync 'apikeys' (checksyncs.py): every node copies apikeys/* from the leader
 global myhost
 _delleader(leaderip, 'sync', 'apikeys_')
 stampv = 'apikeys_'+str(timestamp())
 put(leaderip, 'sync/apikeys/Add_'+name+'/request', stampv)
 put(leaderip, 'sync/apikeys/Add_'+name+'/request/'+myhost, stampv)

def apikey_put(name, rec):
 put(leaderip, 'apikeys/'+name, _apikey_value(rec))

def apikey_clientip():
 try:
  return request.remote_addr or '-'
 except Exception:
  return '-'

def apikey_refused(ip, name, why):
 now = timestamp()
 fails = [t for t in _apikey_fails.get(ip, []) if t > now-APIKEY_FAIL_WINDOW]
 fails.append(now)
 _apikey_fails[ip] = fails
 try:
  if len(fails) <= APIKEY_FAIL_MAX:
   logmsg.sendlog('ApiKeyfa0', 'warning', 'system', str(name)[:40] or '-', ip)
  if len(fails) == APIKEY_FAIL_MAX:
   logmsg.sendlog('ApiKeyfa1', 'warning', 'system', ip)
 except Exception:
  pass
 if len(fails) >= APIKEY_FAIL_MAX:
  _apikey_locked[ip] = now+APIKEY_LOCKOUT
 return {'response': 'baduser'}

def apikey_authenticate(data):
 # returns (None, data prepared) when the key is good, else (reply, None)
 ip = apikey_clientip()
 now = timestamp()
 if _apikey_locked.get(ip, 0) > now:
  return {'response': 'baduser'}, None
 token = str(data.get('token', ''))
 parts = token.split('.', 2)
 if len(parts) != 3 or parts[0] != 'qsk' or not APIKEY_NAME_RE.match(parts[1]) or len(parts[2]) < 32:
  return apikey_refused(ip, parts[1] if len(parts) > 1 else '-', 'malformed'), None
 name, secret = parts[1], parts[2]
 rec = apikeys_all().get(name)
 if not rec:
  return apikey_refused(ip, name, 'unknown'), None
 if not _hmac.compare_digest(_apikey_hash(rec['salt'], secret), rec['hash']) or rec['status'] != 'active':
  return apikey_refused(ip, name, 'bad'), None
 path = request.path
 if path.startswith('/api/v1/apikeys/') or path in APIKEY_NEVER:
  return {'response': 'error', 'message': 'not allowed for an API key'}, None
 if rec['access'] != 'write' and path not in APIKEY_READ:
  return {'response': 'error', 'message': 'key is read only'}, None
 _apikey_fails.pop(ip, None)
 if _apikey_lastwrite.get(name, 0)+APIKEY_LASTUSED_EVERY < now:
  _apikey_lastwrite[name] = now
  rec['lastused'] = datetime.now().strftime('%Y-%m-%dT%H:%M:%S')
  try:
   apikey_put(name, rec)
  except Exception:
   pass
 data['user'] = name
 data['response'] = name
 data['keyaccess'] = rec['access']
 return None, data

def apikey_manager(data):
 # None when the caller (a logged in user, never a key) may manage keys, else the reply
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 if data.get('keyaccess') or not has_privilege('UserPrivilegesch', data['user']):
  return {'response': 'error', 'message': 'not authorized'}
 return None

def apikey_nameclash(name):
 if name in ('admin', 'system', 'root'):
  return True
 try:
  if name in [u['name'].replace('usersinfo/', '') for u in etcdgetjson(leaderip, 'usersinfo', '--prefix')]:
   return True
  if name in [str(g[0]) for g in getgroups()]:
   return True
 except Exception as e:
  print('apikey_nameclash:', e)
 return False

def apikey_newsecret(rec):
 secret = _secrets.token_urlsafe(30)
 rec['salt'] = _secrets.token_hex(16)
 rec['hash'] = _apikey_hash(rec['salt'], secret)
 return secret

def apikey_access(value, default='read'):
 value = str(value or default).lower()
 return value if value in ('read', 'write') else None

def login_required(f):
 global loggedusers
 @wraps(f)
 def decorated_function(*args, **kwargs):
  global loggedusers
  data = request.args.to_dict()
  if 'disks[]' in data:
   data['disks'] = request.args.getlist('disks[]')
   del data['disks[]']
  if 'cache[]' in data:
   data['cache'] = request.args.getlist('cache[]')
   del data['cache[]']
  if 'cache_disks[]' in data:
   data['cache_disks'] = request.args.getlist('cache_disks[]')
   del data['cache_disks[]']


  for dat in data:
   if isinstance(data[dat], str):
    data[dat] = data[dat].replace(' ','')
  data['response'] = 'baduser'
  if str(data.get('token', '')).startswith('qsk.'):
   reply, keydata = apikey_authenticate(data)
   if reply is not None:
    return reply
   return f(keydata)
  if data['token'] in loggedusers:
   if loggedusers[data['token']]['timestamp'] > timestamp():
    data['user'] = loggedusers[data['token']]['user']
    data['response'] = data['user'] 
    return f(data)
   else:
    try:
        logmsg.sendlog('Lognsa0','warning','system',loggedusers[data['token']]['user'])
        return f({'response':'baduser'})
    except:
        return f({'response':'baduser'})
  else:
   try:
    logmsg.sendlog('Lognno0','warning','system1',data['token'])
    return f({'response':'baduser'})
   except:
    return f({'response':'baduser'})
 return decorated_function

def logsafe(d):
 # QSD5.344 (validator L5): what the flask log prints of a request: the secret fields and the login token / API key
 # ('qsk.<name>.<secret>' comes in as token) are masked
 m = masked(d)
 if isinstance(m, dict) and m.get('token') not in (None, ''):
  m = dict(m)
  m['token'] = MASK
 return m

COMMAND_LOG_PATH = '/TopStordata/cmdaudit.log'

def record_command(data, endpoint, method, commands=None):
 try:
  user = data.get('user')
  if not user:
   return
  excluded = ('response', 'user', 'token', 'keyaccess')
  params = dict()
  for k in data:
   if k in excluded:
    continue
   if is_secret_key(k):      # QSD5.344: password, chappas, phrase ... (was only names with 'pass')
    continue
   params[k] = data[k]
  entry = {
   'date': datetime.now().strftime('%m/%d/%Y'),
   'time': datetime.now().strftime('%H:%M:%S'),
   'ts': timestamp(),
   'user': user,
   'source': 'apikey' if data.get('keyaccess') else 'login',
   'host': hostname(),
   'endpoint': endpoint,
   'method': method,
   'params': params,
   'commands': [mask_text(c, _request_secrets(data)) for c in (commands or [])],
  }
  with open(COMMAND_LOG_PATH, 'a') as fh:
   fh.write(json.dumps(entry)+'\n')
 except:
  pass

def get_command_log(user=None, limit=200):
 if not os.path.exists(COMMAND_LOG_PATH):
  return []
 with open(COMMAND_LOG_PATH) as fh:
  rows = fh.readlines()[-5000:]
 entries = []
 for row in reversed(rows):
  row = row.strip()
  if not row:
   continue
  try:
   entry = json.loads(row)
  except:
   continue
  if user and entry.get('user') != user:
   continue
  entries.append(entry)
  if len(entries) >= limit:
   break
 return entries

# ---- request debouncing (QSD5.321): one central guard for every mutating endpoint --------------------------------------
# A human can click OK/Submit many times; every click is a separate request (duplicate volumes, deletes).  The guard keys a
# request by (user or key name, path, hash of its sorted arguments without token/time fields).  An identical request is
# refused while the first is in flight and for DEBOUNCE_SECONDS after the first finished OK; a failed request never blocks
# a retry.  Refusal: HTTP 200 {"response":"duplicate","message":"duplicate request ignored (debounce)"}.
# Callers that really need a quick identical repeat pass nodebounce=1 (API key or localhost callers only).
DEBOUNCE_SECONDS = 3
DEBOUNCE_INFLIGHT_MAX = 180      # an in-flight entry older than this is stale (request lost): no longer blocks
DEBOUNCE_MAX_ENTRIES = 2000      # bound on the memory of the table
DEBOUNCE_PATHS = set('/api/v1/'+x for x in (
 'apikeys/create apikeys/regenerate apikeys/revoke apikeys/delete users/uploadUsers software/setversion software/apply '
 'software/update software/localFileUpdate pools/delpool pools/addtopool pools/delcachespares pools/newpool '
 'pools/updatecache pools/actionOnDisk groups/groupchange replication/addpartner users/userchange '
 'volumes/snapshots/create volumes/create user/changepass hosts/config hosts/joincluster hosts/evacuate '
 'volumes/snapshots/snaprollback volumes/snapshots/perioddelete volumes/snapshots/snapshotdel volumes/volumeactive '
 'volumes/volumedel groups/groupdel partners/partnerdel users/userdel groups/UnixAddgroup partners/AddPartner '
 'tenant/adduser users/UnixAddUser volumes/config users/usersauth').split())
_DEBOUNCE_IGNORE_ARGS = {'token', 'nodebounce', 'timestamp', 'time', 'ts', 't', '_', 'nonce', 'requestid', 'reqid', 'rand'}
_debounce_tbl = {}               # key -> ['inflight'|'done', time]  (done: expiry time)
_debounce_lock = threading.Lock()

def _debounce_key():
    token = str(request.values.get('token', ''))
    if token.startswith('qsk.'):
        who = 'key:'+token.split('.')[1] if len(token.split('.')) > 1 else token
    else:
        try:
            who = 'user:'+str(loggedusers[token]['user'])
        except Exception:
            who = 'tok:'+token
    items = []
    for k in sorted(request.values.keys()):
        if k in _DEBOUNCE_IGNORE_ARGS:
            continue
        items.append((k, sorted(request.values.getlist(k))))
    body = request.get_data(cache=True) if request.is_json else b''
    h = _hashlib.sha1(repr(items).encode('utf-8', 'replace')+body).hexdigest()
    return who+'|'+request.path+'|'+h

def _debounce_exempt():
    if str(request.values.get('nodebounce', '')) != '1':
        return False
    return str(request.values.get('token', '')).startswith('qsk.') or request.remote_addr in ('127.0.0.1', '::1')

@app.before_request
def debounce_before():
    g.debounce_key = None
    try:
        return _debounce_before()
    except Exception:       # the guard itself can never fail a request: fail open
        g.debounce_key = None
        return None

def _debounce_before():
    if request.method not in ('GET', 'POST') or request.path not in DEBOUNCE_PATHS or _debounce_exempt():
        return None
    key = _debounce_key()
    now = time.time()
    with _debounce_lock:
        if len(_debounce_tbl) > DEBOUNCE_MAX_ENTRIES//2:
            for k in [k for k, v in _debounce_tbl.items() if (v[0] == 'done' and v[1] < now) or (v[0] == 'inflight' and v[1]+DEBOUNCE_INFLIGHT_MAX < now)]:
                del _debounce_tbl[k]
            if len(_debounce_tbl) > DEBOUNCE_MAX_ENTRIES:
                _debounce_tbl.clear()
        cur = _debounce_tbl.get(key)
        if cur and ((cur[0] == 'done' and cur[1] > now) or (cur[0] == 'inflight' and cur[1]+DEBOUNCE_INFLIGHT_MAX > now)):
            dup = True
        else:
            dup = False
            _debounce_tbl[key] = ['inflight', now]
            g.debounce_key = key
    if dup:
        print('Debounce: duplicate request ignored', request.path, key.split('|')[0])
        return jsonify({'response': 'duplicate', 'message': 'duplicate request ignored (debounce)'})
    return None

def _debounce_failed(resp):
    if resp.status_code >= 400:
        return True
    try:
        d = resp.get_json(silent=True)
    except Exception:
        d = None
    if isinstance(d, dict):
        r = str(d.get('response', ''))
        return 'baduser' in r or r == 'error' or 'error' in d
    return False

@app.after_request
def debounce_after(resp):
    try:
        key = getattr(g, 'debounce_key', None)
        if key:
            g.debounce_key = None
            with _debounce_lock:
                if _debounce_failed(resp):
                    _debounce_tbl.pop(key, None)
                else:
                    _debounce_tbl[key] = ['done', time.time()+DEBOUNCE_SECONDS]
    except Exception:
        pass
    return resp

@app.after_request
def secrets_out_of_answers(resp):
    # QSD5.344: an answer never carries a password, CHAP secret or pass phrase back (many handlers return the request
    # dict; UnixAddUser and changepass echoed the password, QC test 701).  The login token and an API key shown once on
    # create (field 'key') are not secrets of this kind and stay.
    # Nested objects (the volume lists carry chappas of every iSCSI volume) are masked for the exact secret field names.
    try:
        if resp.mimetype == 'application/json' and not resp.direct_passthrough:
            raw = resp.get_data().lower()
            # 'chappas' does not contain 'pass': without b'chap' a volume list skipped the walk
            if b'pass' not in raw and b'phrase' not in raw and b'secret' not in raw and b'chap' not in raw:
                return resp
            body = resp.get_json(silent=True)
            changed = [False]
            def walk(o, top):
                if isinstance(o, dict):
                    for k in list(o):
                        if (is_secret_key(k) if top else str(k).lower() in MASK_KEYS) and isinstance(o[k], str) \
                           and o[k] not in ('', CHAP_NONE, MASK):
                            o[k] = MASK
                            changed[0] = True
                        else:
                            walk(o[k], False)
                elif isinstance(o, list):
                    for x in o:
                        walk(x, False)
            walk(body, True)
            if changed[0]:
                resp.set_data(json.dumps(body))
    except Exception:
        pass
    return resp

@app.teardown_request
def debounce_teardown(exc):
    try:
        key = getattr(g, 'debounce_key', None)
        if key:      # no after_request ran (unhandled exception): a failed request does not block a retry
            with _debounce_lock:
                _debounce_tbl.pop(key, None)
    except Exception:
        pass

# ---- crash prevention (QSD5.322): parameter guard, safety net, command timeout ----------------------------------------
# Every refusal has the shape of the existing errors: HTTP 200 {"response":"error","message":"..."} (a bad token keeps
# {"response":"baduser"}).  1) before_request guard: body size, value length, required parameters of the changing calls,
# numeric parameters, shell characters in names.  2) errorhandler: any uncaught exception (KeyError of a missing
# parameter, TypeError of a None, ...) and every 404/405/413/415 answers JSON, the trace goes to the log only.
# 3) subprocess.run gets a default timeout, so a hung zfs/etcd command frees the worker.
MAX_BODY_BYTES = 2*1024*1024
MAX_BODY_UPLOAD = 1024*1024*1024         # software/localFileUpdate, users/uploadUsers
MAX_VALUE_LEN = 1000
LONG_VALUE_KEYS = {'users', 'groups', 'auths', 'initiators', 'tochange', 'disks', 'cache', 'cache_disks', 'dompass', 'cacheids'}
SECRET_KEYS = {'token', 'pass', 'Password', 'password', 'dompass', 'oldpass', 'newpass'}
# required parameters per path (presence); keys in NONEMPTY_KEYS must also be non-empty
REQUIRED_PARAMS = {'/api/v1/'+p: v.split() for p, v in {
 'software/setversion': 'version', 'software/apply': 'version', 'pools/delpool': 'pool', 'pools/addtopool': 'pool redundancy',
 'pools/newpool': 'redundancy', 'pools/updatecache': 'host', 'pools/actionOnDisk': 'action actualdisk pool',
 'volumes/snapshots/snaprollback': 'name',
 'volumes/snapshots/perioddelete': 'name', 'volumes/snapshots/snapshotdel': 'name', 'volumes/create': 'type name ipaddress',
 'volumes/volumedel': 'name type', 'volumes/volumeactive': 'name active', 'volumes/config': 'type volume',
 'hosts/evacuate': 'name', 'users/usersauth': 'auths tochange', 'users/userauths': 'username', 'groups/UnixAddgroup': 'name users',
 'groups/groupdel': 'name', 'users/userdel': 'name tenant', 'users/UnixAddUser': 'name', 'partners/partnerdel': 'name',
 'partners/AddPartner': 'alias ip port type', 'tenant/adduser': 'name tenant', 'users/grouplist': 'tenant',
 'hosts/getConfig': 'nodeName', 'users/userhomechange': 'name'}.items()}
# snapshots/create needs a different set per snapsel (QSD5.324: Minutely/Hourly/Weekly send no name)
SNAPSEL_REQUIRED = {'Once': 'name volume pool', 'Minutely': 'volume pool every keep', 'Hourly': 'volume pool sminute every keep',
                    'Weekly': 'volume pool stime every keep'}
NONEMPTY_KEYS = {'name', 'pool', 'volume', 'type', 'version', 'nodeName', 'username', 'alias', 'ip', 'host', 'action',
                 'actualdisk', 'redundancy', 'tenant'}
NUMERIC_KEYS = {'port': r'\d+', 'portalport': r'\d+', 'userid': r'\d+', 'useable': r'\d+(\.\d+)?'}
# names that end up in a shell command line: no shell metacharacters, no path, no leading '-'
SHELLSAFE_KEYS = {'name', 'pool', 'volume', 'owner', 'type', 'alias', 'nodeName', 'username', 'host', 'tenant', 'receiver',
                  'cluster', 'redundancy', 'action', 'version'}
_SHELL_BAD = re.compile(r'[;|&$`<>\\"\'\n\r\x00*?(){}\[\]]|\.\.')
_PATH_BAD_KEYS = {'name', 'pool', 'volume', 'owner', 'alias', 'username', 'tenant', 'receiver'}

def _err(msg, **kw):
    d = {'response': 'error', 'message': msg}
    d.update(kw)
    return jsonify(d)

def _token_ok(token):
    if token.startswith('qsk.'):
        # QC 604 step 1: a forged qsk.* value used to count as 'logged in' here, so the parameter checks below answered
        # 'missing parameter: x' (an unauthenticated caller learned the parameter names of 28 routes) instead of baduser.
        # Only a key that really authenticates passes; every other value falls through to login_required, which refuses
        # it (and counts the attempt, ApiKeyfa0).  Read only: no lock/counter side effects here.
        try:
            parts = token.split('.', 2)
            if len(parts) != 3 or not APIKEY_NAME_RE.match(parts[1]) or len(parts[2]) < 32:
                return False
            rec = apikeys_all().get(parts[1])
            return bool(rec) and rec['status'] == 'active' and _hmac.compare_digest(_apikey_hash(rec['salt'], parts[2]), rec['hash'])
        except Exception:
            return False
    try:
        return token in loggedusers and loggedusers[token]['timestamp'] > timestamp()
    except Exception:
        return False

@app.before_request
def guard_before():
    try:
        return _guard_before()
    except Exception:       # never fail a request because of the guard: the handlers still have their own checks
        return None

def _guard_before():
    path = request.path
    if not path.startswith('/api/v1/') or request.method not in ('GET', 'POST'):
        return None
    limit = MAX_BODY_UPLOAD if path in ('/api/v1/software/localFileUpdate', '/api/v1/users/uploadUsers') else MAX_BODY_BYTES
    if (request.content_length or 0) > limit:
        return _err('request too large')
    if path in ('/api/v1/getAllConfig', '/api/v1/hosts/getAllConfig', '/api/v1/software/update', '/api/v1/software/localFileUpdate'):
        g.cmd_timeout = 900
    args = request.args
    for k in args.keys():
        if k in SECRET_KEYS and k != 'token':
            continue
        for v in args.getlist(k):
            if len(v) > (20000 if k in LONG_VALUE_KEYS else MAX_VALUE_LEN):
                return _err('parameter too long: '+k)
    token = str(args.get('token', ''))
    if path in ('/api/v1/login', '/api/v1/login/test', '/api/v1/logout') or not _token_ok(token):
        return None          # login_required answers baduser in its own format
    req = REQUIRED_PARAMS.get(path, ())
    if path == '/api/v1/volumes/snapshots/create':
        req = ['snapsel'] + SNAPSEL_REQUIRED.get(args.get('snapsel'), 'volume pool').split()
    for k in req:
        v = args.get(k)
        if v is None or (k in NONEMPTY_KEYS and not str(v).strip()):
            return _err('missing parameter: '+k)
    for k, pat in NUMERIC_KEYS.items():
        v = args.get(k)
        if v not in (None, '') and not re.fullmatch(pat, str(v).strip()):
            return _err('parameter must be a number: '+k)
    if path in DEBOUNCE_PATHS:
        for k in SHELLSAFE_KEYS:
            for v in args.getlist(k):
                v = str(v)
                if _SHELL_BAD.search(v) or v.startswith('-') or (k in _PATH_BAD_KEYS and ('/' in v or '\\' in v)):
                    return _err('invalid character in parameter: '+k)
    return None

_orig_subprocess_run = subprocess.run
def _run_with_timeout(*a, **kw):
    if kw.get('timeout') is None:
        try:
            kw['timeout'] = getattr(g, 'cmd_timeout', 120) if flask.has_request_context() else 120
        except Exception:
            kw['timeout'] = 120
    return _orig_subprocess_run(*a, **kw)
subprocess.run = _run_with_timeout

@app.errorhandler(Exception)
def safety_net(exc):
    from werkzeug.exceptions import HTTPException
    if isinstance(exc, HTTPException):
        msgs = {400: 'bad request', 404: 'not found', 405: 'method not allowed', 413: 'request too large',
                415: 'unsupported content type'}
        return _err(msgs.get(exc.code, 'request refused')), (exc.code if exc.code in msgs else 400)
    try:
        print('Unhandled exception in', request.method, request.path, '\n', traceback.format_exc())
    except Exception:
        pass
    if isinstance(exc, KeyError):
        k = str(exc.args[0]) if exc.args else ''
        if k == 'token':
            return jsonify({'response': 'baduser'})
        return _err('missing parameter: '+k)
    if isinstance(exc, subprocess.TimeoutExpired):
        return _err('the command timed out')
    if isinstance(exc, (TypeError, ValueError, IndexError, AttributeError)):
        return _err('invalid or missing parameter')
    return _err('internal error')


def audit_command(f):
 @wraps(f)
 def decorated_function(data, *args, **kwargs):
  _cmdctx.commands = []
  try:
   result = f(data, *args, **kwargs)
  finally:
   cmds = getattr(_cmdctx, 'commands', [])
   _cmdctx.commands = None
   try:
    record_command(data, request.path, request.method, cmds)
   except:
    pass
  return result
 return decorated_function

@app.route('/api/v1/apikeys/list', methods=['GET','POST'])
@login_required
@audit_command
def apikeys_list(data):
 refused = apikey_manager(data)
 if refused:
  return refused
 allkeys = []
 for name, rec in sorted(apikeys_all().items()):
  allkeys.append({'name': name, 'access': rec['access'], 'status': rec['status'], 'created': rec['created'],
                  'createdby': rec['createdby'], 'lastused': rec['lastused'], 'revoked': rec['revoked']})
 return {'response': 'Ok', 'allkeys': allkeys}

@app.route('/api/v1/apikeys/create', methods=['GET','POST'])
@login_required
@audit_command
def apikeys_create(data):
 refused = apikey_manager(data)
 if refused:
  return refused
 name = str(data.get('name', ''))
 access = apikey_access(data.get('access'))
 if not APIKEY_NAME_RE.match(name):
  return {'response': 'error', 'message': 'name must be 3-32 characters: letters, digits, _ or -, starting with a letter'}
 if access is None:
  return {'response': 'error', 'message': 'access must be read or write'}
 if name in apikeys_all():
  return {'response': 'error', 'message': 'a key with this name already exists'}
 if apikey_nameclash(name):
  return {'response': 'error', 'message': 'the name is already used by a user or a group'}
 rec = {'access': access, 'status': 'active', 'created': datetime.now().strftime('%Y-%m-%dT%H:%M:%S'),
        'createdby': data['user'], 'lastused': '-', 'revoked': '-', 'salt': '', 'hash': ''}
 secret = apikey_newsecret(rec)
 apikey_put(name, rec)
 apikey_sync(name)
 logmsg.sendlog('ApiKey1000', 'info', data['user'], name)
 return {'response': 'Ok', 'name': name, 'access': access, 'key': 'qsk.'+name+'.'+secret}

@app.route('/api/v1/apikeys/regenerate', methods=['GET','POST'])
@login_required
@audit_command
def apikeys_regenerate(data):
 refused = apikey_manager(data)
 if refused:
  return refused
 name = str(data.get('name', ''))
 rec = apikeys_all().get(name)
 if not rec:
  return {'response': 'error', 'message': 'no such key'}
 access = apikey_access(data.get('access'), rec['access'])
 if access is None:
  return {'response': 'error', 'message': 'access must be read or write'}
 rec.update({'access': access, 'status': 'active', 'revoked': '-', 'lastused': '-',
             'created': datetime.now().strftime('%Y-%m-%dT%H:%M:%S'), 'createdby': data['user']})
 secret = apikey_newsecret(rec)
 apikey_put(name, rec)
 apikey_sync(name)
 logmsg.sendlog('ApiKey1001', 'info', data['user'], name)
 return {'response': 'Ok', 'name': name, 'access': access, 'key': 'qsk.'+name+'.'+secret}

@app.route('/api/v1/apikeys/revoke', methods=['GET','POST'])
@login_required
@audit_command
def apikeys_revoke(data):
 refused = apikey_manager(data)
 if refused:
  return refused
 name = str(data.get('name', ''))
 rec = apikeys_all().get(name)
 if not rec:
  return {'response': 'error', 'message': 'no such key'}
 rec['status'] = 'revoked'
 rec['revoked'] = datetime.now().strftime('%Y-%m-%dT%H:%M:%S')
 apikey_put(name, rec)
 apikey_sync(name)
 logmsg.sendlog('ApiKey1002', 'info', data['user'], name)
 return {'response': 'Ok', 'name': name, 'status': 'revoked'}

@app.route('/api/v1/apikeys/delete', methods=['GET','POST'])
@login_required
@audit_command
def apikeys_delete(data):
 refused = apikey_manager(data)
 if refused:
  return refused
 name = str(data.get('name', ''))
 if name not in apikeys_all():
  return {'response': 'error', 'message': 'no such key'}
 _delleader(leaderip, 'apikeys/'+name)
 apikey_sync(name)
 logmsg.sendlog('ApiKey1003', 'info', data['user'], name)
 return {'response': 'Ok', 'name': name}


@app.route('/api/v1/users/uploadUsers', methods=['GET','POST'])
@login_required
@audit_command
def uploadUsers(data):
    global allgroups, leaderip, myhost
    if 'baduser' in data['response']:
      return {'response': 'baduser'}
    # QSD5.352 r4 (validator N2): no privilege check: any logged-in user (e.g. Logs only) could add users in bulk, and the client's
    # file name went into the path raw ('../../TopStor/x.sh' or '/TopStor/x.sh' wrote into the code tree).  Same privilege as
    # users/UnixAddUser (Box_Users, the Users page), checked before the upload is read; the file is saved as its base name only.
    if not has_privilege('Box_Users', data.get('user')):
      logmsg.sendlog('Priv1004','error','system',str(data.get('user')))
      return {'response': data.get('response'), 'error': 'noprivilege'}
    uploaded_file = request.files['file']
    if uploaded_file.filename != '':
      filename = upload_name(uploaded_file.filename)
      # QSD5.352 r5 (validator N3): saved in /TopStordata/uploads, never over a /TopStordata file; a symlink is refused
      filePath = save_upload(uploaded_file, filename) if filename is not None else None
      if filePath is None:
        logmsg.sendlog('Unlin1026', 'error', data["user"])
        return {'response': data.get('response'), 'error': 'badfilename'}
      cmdline = 'python /TopStor/UsersMassAddition.py '+ leaderip +' '+ data['user'] + ' ' + myhost + ' ' + filePath + ' '+ data['token']
      # "adding users started" before the job is queued, so it is always logged ahead of the rows and Unlin1027
      logmsg.sendlog('Unlin1025', 'info', data["user"])
      postchange(cmdline)
      return {"data":data}
    else:
      logmsg.sendlog('Unlin1026', 'error', data["user"])
      return 'Error while uploading file!'


def postchange(cmndstring,host='leader'):
 global leaderip, myhost, myhostip
 z= cmndstring.split(' ')
 if 'leader' in host:
    host=myhost
 msg={'req': 'Pumpthis', 'reply':z}
 if myhost in host:
     ownerip=myhostip
 else:
    try:
        ownerip=get('ready/'+host,'--prefix')[0][1]
    except:
        return 'host is not ready'
 # merge M+A: no copy of the command in /TopStordata/tempdata any more (A, test 619: a 644 debug log with the plaintext
 # passwords); the message-bus log line gets the request's secrets masked (M, QSD5.344 QC test 701)
 logline = mask_text(str(msg), _request_secrets())
 sendhost(ownerip, str(msg),'recvreply',myhost, logreq=logline)
 return 'queued'

def _request_secrets(data=None):
 # the secret values of the current request (as sent and without blanks), for masking what is written down
 vals = []
 try:
  if flask.has_request_context():
   vals = secret_values(request.values.to_dict())
 except Exception:
  vals = []
 if data:
  vals = sorted(set(vals) | set(secret_values(data)), key=len, reverse=True)
 return vals

def dict_factory(cursor, row):
    d = {}
    for idx, col in enumerate(cursor.description):
        d[col[0]] = row[idx]
    return d

# usersinfo/<user> = <uid>/<pool>/<home>/<size>/<privileges...>: a row with fewer than 4 '/' fields (e.g. '_1/Logs-true' that
# Priv.py wrote for a user that did not exist before QSD5.321) or etcdget's '_1' / '-1' for a missing key is not a user
def usersinfo_ok(prop):
 prop = str(prop) if prop is not None else ''
 if prop in ('', '_1', '-1', 'None'):
  return False
 fields = prop.split('/')
 return len(fields) >= 4 and fields[0] not in ('_1', '-1', '')

_usersinfo_badlogged = set()
def usersinfo_badrow(username, prop):
 # printed once per row value (fapi's stderr), not on every list call
 key = str(username)+'='+str(prop)
 if key not in _usersinfo_badlogged:
  _usersinfo_badlogged.add(key)
  print('fapi: skipping malformed usersinfo row usersinfo/'+key, file=sys.stderr)

def getusers():
 global leaderip
 userlst = etcdgetjson(leaderip,'usersinfo','--prefix') 
 uid = 0
 users = []
 for user in userlst:
  username = user['name'].replace('usersinfo/','')
  users.append([username,str(uid)]) 
  uid += 1
 return users

def groupnames_from(grps, allgroups):
 """Group names for a comma list of group NAMES (what the UI sends) or numeric group ids/indexes (older callers).
 Returns None when an entry matches neither."""
 names = []
 for grp in str(grps).split(','):
  grp = grp.strip()
  if not grp:
   continue
  gname = None
  for agrp in allgroups:
   if str(agrp[0]) == grp:
    gname = agrp[0]
    break
  if gname is None:
   try:
    gname = allgroups[int(grp)][0]
   except (ValueError, IndexError):
    return None
  if gname not in names:
   names.append(gname)
 return ','.join(names)

def share_groups(grps):
 # QSD5.352 (QC 698 finding 4): a share created / changed with group IDS (the 'id' of groups/grouplist, as users take
 # them) got the digits as its write list, which no user is a member of; the share had to be made again with the name.
 # Digit entries that are not a group name are turned into group names; an unknown id refuses the call (None).
 toks = [ t.strip() for t in str(grps).split(',') if t.strip() ]
 if not any(t.isdigit() for t in toks):
  return grps
 allg = getgroups()
 names = set(g[0] for g in allg)
 out = []
 for t in toks:
  if t in names or not t.isdigit():
   out.append(t)
   continue
  n = groupnames_from(t, allg)
  if n is None:
   return None
  out.append(n)
 return ','.join(out)

def getgroups():
 global leaderip
 groupslst = etcdgetjson(leaderip, 'usersigroup','--prefix') 
 gid = 0
 groups = []
 for group in groupslst:
  grpusers = group['prop'].split('/')[2]
  groupname = group['name'].replace('usersigroup/','')
  groups.append([groupname,str(gid), grpusers]) 
  gid += 1
 return groups

@app.route('/', methods=['GET'])
def home():
    return '''<h1>Distant Reading Archive</h1>
<p>A prototype API for distant reading of science fiction novels.</p>'''

def gettenants():
 global leaderip
 vols = get('vol','/NFS/')
 volinfo = []
 pid = 0
 for vol in vols:
  if 'active' not in vol[1]:
    continue
  volinfo.append({'id':pid, 'pool': vol[0].split('/')[3], 'text':vol[0].split('/')[4]})
  pid += 1
 return volinfo

def getpools():
 global pooldict, leaderip
 pools = get('pools/','--prefix')
 poolinfo = []
 pid = 0
 for pool in pools:
  poolinfo.append({'id':pid, 'owner': pool[1], 'text':pool[0].split('/')[1]})
  pid += 1
  pooldict[pool[0].split('/')[1]] = {'id': pid, 'owner': pool[1] }
 return poolinfo

@app.route('/api/v1/volumes/connections', methods=['GET','POST'])
@login_required
@audit_command
def getconns(data):
 global leaderip
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 # QSD5.344 (test 658 QX-059 step 3): every node writes the clients of its volumes (CIFS, NFS, iSCSI) to
 # connections/<node> = {"stamp", "node", "connections": [...]} (pace/activeusers.py from zfsping, ~30 s). A node whose stamp
 # is older than 90 s (dead node, stopped collector) is left out. Before, connections/user and connections/dev were read,
 # which nothing wrote.
 conndict =  {}
 conndict['connections'] = []
 now = timestamp()
 for node in get('connections/','--prefix'):
  try:
   nodeconns = json.loads(node[1])
   if now - float(nodeconns['stamp']) > 90:
    continue
   for conn in nodeconns['connections']:
    conn['device'] = conn.get('client','')	# the field of the old answer
    conndict['connections'].append(conn)
  except Exception:
   continue
 conndict['response'] = data['response']
 return conndict 


@app.route('/api/v1/software/setversion', methods=['GET','POST'])
@login_required
@audit_command
def setversion(data):
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 # QSD5.352 r3 (validator N1): no privilege check: any logged-in user (e.g. Logs only) could run updateversion (set the
 # software version). Same rule as software/update (R4): the Updates page needs Uploadch.
 if not has_privilege('Uploadch', data.get('user')):
  logmsg.sendlog('Priv1004','error','system',str(data.get('user')))
  return {'response': data.get('response'), 'error': 'noprivilege'}
 versions = getversions()
 if data['version'] in versions['versions'] and data['version'] not in versions['current']:
  cmdline = '/TopStor/updateversion '+data['version']
  postchange(cmdline)
 return data 

@app.route('/api/v1/software/versions', methods=['GET','POST'])
@login_required
@audit_command
def versions(data):
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 res = getversions()
 res['response'] = data['response']
 return res

@app.route('/api/v1/software/apply', methods=['GET','POST'])
@login_required
@audit_command
def swapply(data):
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 # QSD5.352 r3 (validator N1): no privilege check: any logged-in user (e.g. Logs only) could run systemcheckout.sh (move
 # the cluster to another software version). Same rule as software/update (R4): the Updates page needs Uploadch.
 if not has_privilege('Uploadch', data.get('user')):
  logmsg.sendlog('Priv1004','error','system',str(data.get('user')))
  return {'response': data.get('response'), 'error': 'noprivilege'}
 cmdline = '/TopStor/systemcheckout.sh '+data['version'].split(',')[0]+' '+data['response']+' '+'hi1'
 postchange(cmdline)
 versionlst = versions(data)
 versionlst['response'] = data['response']
 return versionlst


#@app.route('/api/v1/hosts/info', methods=['GET','POST'])
def hostsinfo():
 global allhosts, readyhosts, activehosts, losthosts, possiblehosts
 allhosts = Hostsconfig.getall()
 return jsonify(allhosts)

@app.route('/api/v1/hosts/allinfo', methods=['GET','POST'])
@login_required
@audit_command
def hostsallinfo(data):
 global allhosts, readyhosts, activehosts, losthosts, possiblehosts
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 hostsinfo()
 hostslost()  
 hostspossible()
 return jsonify({'all': allhosts, 'active': activehosts, 'ready':readyhosts, 'possible':possiblehosts, 'lost':losthosts})


#@app.route('/api/v1/hosts/ready', methods=['GET','POST'])
def hostsready():
 global allhosts, readyhosts, activehosts, losthosts, possiblehosts, leaderip
 hosts = get('ready','--prefix')
 readyhosts = []
 hid = 0
 for host in hosts:
  name = host[0].replace('ready/','')
  ip = host[1]
  readyhosts.append({'name':name, 'ip': ip, 'id': hid}) 
  hid +=1
 return jsonify(readyhosts)

#@app.route('/api/v1/hosts/active', methods=['GET','POST'])
def hostsactive():
 global allhosts, readyhosts, activehosts, losthosts, possiblehosts, leaderip
 hosts = get('ActivePartners','--prefix')
 activehosts = []
 hid = 0
 for host in hosts:
  name = host[0].replace('ActivePartners/','')
  ip = host[1]
  activehosts.append({'name':name, 'ip': ip, 'id': hid}) 
  hid +=1
 return jsonify(activehosts)


@app.route('/api/v1/hosts/syncnow', methods=['GET','POST'])
@login_required
@audit_command
def hostssyncnow(data):
 # "Nodes Not in Sync" -> Sync now: every ready node applies the pending sync requests at once (the step its
 # syncrequestlooper repeats on its own), so the cluster does not wait for the next round of the loop
 global leaderip
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 asked = []
 for host in get('ready','--prefix'):
  name = host[0].replace('ready/','')
  postchange('/pace/checksyncs.py syncrequest '+leaderip+' '+name+' '+host[1], name)
  asked.append(name)
 data['syncnow'] = asked
 return data

@app.route('/api/v1/hosts/discover', methods=['GET','POST'])
@login_required
@audit_command
def discover(data):
    if 'baduser' in data['response']:
      return {'response': 'baduser'}
    cmndstring = '/TopStor/getdiscovery.sh '
    postchange(cmndstring)
    return data 

#@app.route('/api/v1/hosts/possible', methods=['GET','POST'])
def hostspossible():
 global allhosts, readyhosts, activehosts, losthosts, possiblehosts, leaderip
 hosts = get('possible','--prefix')
 possiblehosts = []
 hid = 0
 for host in hosts:
  name = host[0].split('/')[1]
  ip = host[1]
  possiblehosts.append({'name':name, 'ip': ip, 'id': hid}) 
  hid +=1
 return jsonify(possiblehosts)

#@app.route('/api/v1/hosts/lost', methods=['GET','POST'])
def hostslost():
 global allhosts, readyhosts, activehosts, losthosts, possiblehosts
 hostsready()
 hostsactive()
 losthosts = []
 hid = 0
 for active in activehosts:
  if active['name'] not in str(readyhosts): 
   losthosts.append({'id': hid, 'name': active['name'], 'ip': active['ip']})
  hid += 1
 return jsonify(losthosts)

# QSD5.326, test 633 (QX-034) step 2: pools/delpool only queues DGdestroyPool on the owner and answers at once; the pool and
# its disks stay in 'host current' for some 30-40 s (DGst5 .. DGsu5 .. putzpool).  A newpool/addtopool sent right after the
# delete found 0 free disks, newraids() had no key for the layout and dgsinfo['newraid'][redundancy] raised KeyError -> 500.
# delpool now remembers the pools it queued for deletion (this process only: the API runs on the leader) and the pool calls
# wait (bounded) for those pools to leave the inventory before they compute the free layouts.
POOLDEL_WAIT = 90                    # longest wait of one pool call for a pending delete (s)
POOLDEL_POLL = 3                     # inventory refresh interval while waiting (s)
POOLDEL_FORGET = 300                 # a delete still not visible after this is forgotten (failed or refused, DGfa5)
_pooldel_pending = {}                # pool -> time its delete was queued
_pooldel_lock = threading.Lock()

def _pooldel_busy():
 # pools whose queued delete is not finished in the current inventory (the pool or one of its disks is still listed)
 now = timestamp()
 with _pooldel_lock:
  for pool, queued in list(_pooldel_pending.items()):
   still = pool in allinfo.get('pools', {}) or any(str(d.get('pool', '')) == pool for d in allinfo.get('disks', {}).values())
   if not still or now - queued > POOLDEL_FORGET:
    _pooldel_pending.pop(pool, None)
  return sorted(_pooldel_pending)

def _useable(value):
 # useable arrives as a string ("64.2") from the API clients while the size keys of newraids() are floats
 try:
  return float(value)
 except (TypeError, ValueError):
  return value

def _sizeavailable(newraid, redundancy, useable):
 return redundancy in newraid and len(newraid[redundancy]) > 0 and useable in newraid[redundancy]

def _newraid_after_pooldel(redundancy, useable):
 # newraids() of the inventory; while the exact layout/size is missing and a delete is pending, refresh and wait (bounded).
 # Returns (newraid, busy pools); busy is not empty only when the wait ran out.
 newraid = newraids(_diskinventory())
 waited = 0
 busy = _pooldel_busy()
 while busy and not _sizeavailable(newraid, redundancy, useable) and waited < POOLDEL_WAIT:
  _poolop_sleep(POOLDEL_POLL)
  waited += POOLDEL_POLL
  getalltime('yes')
  newraid = newraids(_diskinventory())
  busy = _pooldel_busy()
 if _sizeavailable(newraid, redundancy, useable):
  busy = []
 return newraid, busy

def _pooldel_conflict(busy):
 return jsonify({'response': 'error', 'pools': busy,
                 'message': 'requested layout/size not available (disks busy: pool delete in progress)'}), 409

# QSD5.330 (test 637 QX-038 step 3): Flask serves requests in threads; two parallel newpool calls ran the disk selection at the
# same time (fastselect keeps its working state in module globals -> one call raised -> HTTP 500), and neither call knew the
# disks the other had just queued (the new pool is in the inventory only after DGsetPool ran), so both could pick the same disks.
# Now newpool/addtopool/delpool run one at a time (_poolop_lock, from the inventory refresh to postchange; released while
# _newraid_after_pooldel sleeps), and the disks a create/add queued are left out of later selections until the inventory shows
# them in a pool (or POOLNEW_FORGET passed: the create failed). A layout that does not fit then is a deliberate 409.
POOLNEW_FORGET = 300                 # a queued create whose disks are still free after this is forgotten (s)
_poolnew_pending = {}                # disk -> time a create/add with it was queued
_poolop_lock = threading.Lock()
_poolop_ctx = threading.local()      # .held: this thread holds _poolop_lock

def _pool_serialised(f):
 @wraps(f)
 def decorated_function(*args, **kwargs):
  with _poolop_lock:
   _poolop_ctx.held = True
   try:
    return f(*args, **kwargs)
   finally:
    _poolop_ctx.held = False
 return decorated_function

def _poolop_sleep(seconds):
 # sleep without blocking the other pool calls (the caller holds _poolop_lock)
 if getattr(_poolop_ctx, 'held', False):
  _poolop_lock.release()
  try:
   sleep(seconds)
  finally:
   _poolop_lock.acquire()
 else:
  sleep(seconds)

def _poolnew_busy():
 # disks of a queued create/add that the inventory does not show in a pool yet
 now = timestamp()
 disks = allinfo.get('disks', {})
 with _pooldel_lock:
  for disk, queued in list(_poolnew_pending.items()):
   seen = disks.get(disk)
   inpool = seen is not None and 'free' not in str(seen.get('raid', 'free'))
   if inpool or now - queued > POOLNEW_FORGET:
    _poolnew_pending.pop(disk, None)
  return set(_poolnew_pending)

def _poolnew_queued(disks):
 with _pooldel_lock:
  for disk in disks:
   _poolnew_pending[disk] = timestamp()

def _diskinventory():
 # allinfo['disks'] without the disks of queued creates/adds
 busy = _poolnew_busy()
 return {disk: info for disk, info in allinfo['disks'].items() if disk not in busy}

def _poolnew_conflict(busy):
 return jsonify({'response': 'error', 'disks': sorted(busy),
                 'message': 'requested layout/size not available (disks busy: pool create in progress)'}), 409

@app.route('/api/v1/pools/dgsinfo', methods=['GET','POST'])
@login_required
@audit_command
def dgsinfo(data):
 global allinfo 
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 getalltime()
 dgsinfo = {'raids':allinfo['raids'], 'pools':allinfo['pools'], 'disks':allinfo['disks']}
 dgsinfo['newraid'] = newraids(allinfo['disks'])
 return jsonify(dgsinfo)

@app.route('/api/v1/pools/delpool', methods=['GET','POST'])
@login_required
@audit_command
@_pool_serialised
def dgsdelpool(data):
 global allinfo, myhost
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 getalltime()
 # a pool that still holds volumes (NFS/CIFS/HOME/iSCSI) is not destroyed: their share containers and targets use its
 # datasets, so the forced export/destroy would hang (container flavour) or cut running clients
 if any(vinfo.get('pool') == data['pool'] for vinfo in allinfo['volumes'].values()):
  logmsg.sendlog('DGfa25','error','system',data['pool'])
  data['error'] = 'poolhasvolumes'
  return jsonify(data)
 data['owner'] = allinfo['pools'][data['pool']]['host']
 ownerip = allinfo['hosts'][data['owner']]['ipaddress']
 datastr = data['pool']+' '+data['user'] 
 cmndstring = '/TopStor/DGdestroyPool '+leaderip+' '+datastr
 if postchange(cmndstring,data['owner']) == 'queued':
  with _pooldel_lock:
   _pooldel_pending[data['pool']] = timestamp()
# z= cmndstring.split(' ')
# msg={'req': 'Pumpthis', 'reply':z}
# sendhost(ownerip, str(msg),'recvreply',myhost)
 return jsonify(data)

# QSD5.332: the vdev type a redundancy of addtopool adds ('raid6plus' before 'raid6', 'raid60'/'raid50' share their prefix);
# None = not known here (the request goes on as before)
def _addlayout(redundancy):
 r = str(redundancy)
 if 'volset' in r or 'single' in r:
  return 'stripe'
 if 'mirror' in r or 'raid10' in r:
  return 'mirror'
 if 'raid6plus' in r:
  return 'raidz3'
 if 'raid6' in r:
  return 'raidz2'
 if 'raid5' in r:
  return 'raidz1'
 return None

# the vdev types of a pool's data groups (allinfo['pools'][pool]['raids'] is in zpool status order: the data groups come
# before the logs/cache/spares/special/dedup sections, whose own mirrors are not data groups). Empty = not known.
def _pooldatalayouts(poolinfo):
 layouts = []
 if not poolinfo:
  return layouts
 for raid in poolinfo.get('raids', []):
  name = str(raid)
  if name.startswith(('log', 'cache', 'spare', 'special', 'dedup')):
   break
  if name.startswith('mirror'):
   layout = 'mirror'
  elif name.startswith('raidz3'):
   layout = 'raidz3'
  elif name.startswith('raidz2'):
   layout = 'raidz2'
  elif name.startswith('raidz'):
   layout = 'raidz1'
  elif name.startswith('stripe'):
   layout = 'stripe'
  else:
   continue
  if layout not in layouts:
   layouts.append(layout)
 return layouts

@app.route('/api/v1/pools/addtopool', methods=['GET','POST'])
@login_required
@audit_command
@_pool_serialised
def dgsaddtopool(data):
 global allinfo, myhost, leaderip
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 getalltime('yes')
 keys = []
 dgsinfo = {'raids':allinfo['raids'], 'pools':allinfo['pools'], 'disks':allinfo['disks']}
 # QSD5.332 (test 639 QX-040 step 4): the requested group must have the layout of the pool's data groups; a single/volset
 # (stripe) group on a mirror/raidz pool removed its redundancy (volset: zpool add -f) or crashed (single: HTTP 500)
 wanted = _addlayout(data['redundancy'])
 poollayouts = _pooldatalayouts(dgsinfo['pools'].get(data['pool']))
 if wanted and poollayouts and wanted not in poollayouts:
  poollayout = '+'.join(poollayouts)
  requested = data['redundancy']+'('+wanted+')'
  logmsg.sendlog('DGfa26','error',data['user'],data['pool'],poollayout,requested)
  return jsonify({'response': 'error', 'error': 'mismatchedredundancy', 'pool': data['pool'], 'poollayout': poollayout,
                  'requested': data['redundancy'],
                  'message': 'mismatched redundancy: pool '+data['pool']+' is '+poollayout+', the requested '+requested
                             +' group does not match its layout; group not added'}), 400
 data['useable'] = _useable(data['useable'])
 dgsinfo['newraid'], busy = _newraid_after_pooldel(data['redundancy'], data['useable'])
 if busy:
  return _pooldel_conflict(busy)
 freedisks = _diskinventory()
 if not dgsinfo['newraid'].get(data['redundancy']) and _poolnew_busy():
  return _poolnew_conflict(_poolnew_busy())
 if not dgsinfo['newraid'].get(data['redundancy']):
  return jsonify({'response': 'error',
                  'message': 'No eligible data disks are available for this configuration'}), 400
 if data['useable'] not in dgsinfo['newraid'][data['redundancy']]:
  keys = list(dgsinfo['newraid'][data['redundancy']].keys())
  keys.append(float(data['useable']))
  keys.sort()
  diskindx = keys.index(float(data['useable'])) + 1
  if diskindx == len(keys):
   diskindx = len(keys) - 2 
  data['useable'] = keys[diskindx]
 disks =  dgsinfo['newraid'][data['redundancy']][data['useable']]
 if 'single' in data['redundancy']:
  selecteddisks = disks
 elif 'raid10' in data['redundancy']:
  bestdisks = selectraid10(leaderip,disks,freedisks,data['pool'])
  if len(bestdisks) < 1:
    return jsonify(data)
  selecteddisks = bestdisks.split(',')
 elif 'raid50' in data['redundancy']:
  bestdisks = selectraid50(leaderip,disks,freedisks,data['pool'])
  if len(bestdisks) < 1:
    return jsonify(data)
  selecteddisks = bestdisks.split(',')
 elif 'raid60' in data['redundancy']:
  bestdisks = selectraid60(leaderip,disks,freedisks,data['pool'])
  if len(bestdisks) < 1:
    return jsonify(data)
  selecteddisks = bestdisks.split(',')
 else:
  print('#########################')
  print('disks',disks)
  print('#########################')
  bestdisks = selectdisks(leaderip,disks,freedisks,data['pool'])
  print('bestdisks',bestdisks)
  print('#########################')
  if len(bestdisks) < 1:
    return jsonify(data)
  selecteddisks = bestdisks.split(',')
 data['owner'] = allinfo['pools'][data['pool']]['host']
 ownerip = allinfo['hosts'][data['owner']]['ipaddress']
 diskstring = ''
 for dsk in selecteddisks:
  diskstring += dsk+":"+dsk[-5:]+" "
 if 'mirror' in data['redundancy']:
  datastr = 'addmirror '+data['user']+' '+data['owner']+" "+diskstring+data['pool']
 elif 'volset' in data['redundancy']:
  datastr = 'addstripeset '+data['user']+' '+data['owner']+" "+diskstring+data['pool']
 elif 'raid5' in data['redundancy'] and 'raid50' not in data['redundancy']:     # 'raid5' is a substring of 'raid50': a RAID50 request used to be created as one big single-parity group (QSD5.269)
  datastr = 'addparity '+data['user']+' '+data['owner']+" "+diskstring+data['pool']
 elif 'raid6plus' in data['redundancy']:
  datastr = 'addparity3 '+data['user']+' '+data['owner']+" "+diskstring+data['pool']
 elif 'raid10' in data['redundancy']:
  datastr = 'addraid10 '+data['user']+' '+data['owner']+" "+diskstring+data['pool']
 elif 'raid50' in data['redundancy']:
  datastr = 'addraid50w'+str(raidwidthof('raid50',selecteddisks,allinfo['disks']))+' '+data['user']+' '+data['owner']+" "+diskstring+data['pool']
 elif 'raid60' in data['redundancy']:
  datastr = 'addraid60w'+str(raidwidthof('raid60',selecteddisks,allinfo['disks']))+' '+data['user']+' '+data['owner']+" "+diskstring+data['pool']
 elif 'raid6' in data['redundancy']:
  datastr = 'addparity2 '+data['user']+' '+data['owner']+" "+diskstring+data['pool']
 else:
  # no add command for this layout (e.g. 'single'): a deliberate 400, never an unhandled 500
  return jsonify({'response': 'error', 'error': 'unsupportedredundancy', 'requested': data['redundancy'],
                  'message': 'unsupported redundancy for adding to a pool: '+str(data['redundancy'])}), 400
 cmndstring = '/TopStor/DGsetPool '+leaderip+' '+datastr
 if postchange(cmndstring,data['owner']) == 'queued':
  _poolnew_queued(selecteddisks)
# z= cmndstring.split(' ')
# msg={'req': 'Pumpthis', 'reply':z}
# sendhost(ownerip, str(msg),'recvreply',myhost)
 return jsonify(data)
 
@app.route('/api/v1/pools/cachespares', methods=['GET', 'POST'])
@login_required
@audit_command
def dgscachespares(data):
    global allinfo, myhost, leaderip

    if 'baduser' in data['response']:
        return {'response': 'baduser'}

    try:
        cache_disks = data.get('cache_disks', [])
        if not cache_disks:
            return jsonify({'response': 'success', 'message': 'No disks to add.'})

        disk_ids_to_store = []
        for disk_id in cache_disks:
            if disk_id.startswith('/dev/disk/by-id/'):
                disk_ids_to_store.append(disk_id.split('/')[-1])
            else:
                disk_ids_to_store.append(disk_id)

        disks_str = " ".join(disk_ids_to_store)
        cmndstring = f"/TopStor/cachedisks.py add {leaderip} {disks_str}"
        postchange(cmndstring)

        return jsonify({
            'response': 'success',
            'message': f'Queued adding of {len(disk_ids_to_store)} spare cache disks.'
        })

    except Exception as e:
        return jsonify({
            'response': 'error',
            'message': f'Failed to process spare cache list via etcd: {str(e)}'
        }), 500

@app.route('/api/v1/pools/delcachespares', methods=['GET', 'POST'])
@login_required
@audit_command
def dgsdelcachespares(data):
    global allinfo, myhost, leaderip

    if 'baduser' in data['response']:
        return {'response': 'baduser'}

    try:
        disks_to_remove = data.get('cache_disks', [])

        if not disks_to_remove:
            return jsonify({'response': 'error', 'message': 'No disks provided'}), 400

        disks_str = " ".join(disks_to_remove)

        cmndstring = f"/TopStor/cachedisks.py del {leaderip} {disks_str}"
        postchange(cmndstring)

        return jsonify({
            'response': 'success',
            'message': f'Queued removal of {len(disks_to_remove)} cache disks'
        })

    except Exception as e:
        print(f"Error processing request: {e}")
        return jsonify({
            'response': 'error',
            'message': f'Failed to queue cache disk removal: {str(e)}'
        }), 500

@app.route('/api/v1/pools/newpool', methods=['GET','POST'])
@login_required
@audit_command
@_pool_serialised
def dgsnewpool(data):
    global allinfo, myhost, leaderip

    if 'baduser' in data['response']:
        return {'response': 'baduser'}

    getalltime('yes')

    manual_cache = data.get('cache')
    if not isinstance(manual_cache, list):
        manual_cache = []
    excluded_disks = ','.join(manual_cache)

    if data.get('disks'):
        selecteddisks = data['disks']
        busy = _poolnew_busy() & set(selecteddisks)
        if busy:
            return _poolnew_conflict(busy)
    else:
        keys = []
        dgsinfo = {'raids':allinfo['raids'], 'pools':allinfo['pools'], 'disks':allinfo['disks']}
        data['useable'] = _useable(data['useable'])
        dgsinfo['newraid'], busy = _newraid_after_pooldel(data['redundancy'], data['useable'])
        if busy:
            return _pooldel_conflict(busy)
        freedisks = _diskinventory()
        if not dgsinfo['newraid'].get(data['redundancy']) and _poolnew_busy():
            return _poolnew_conflict(_poolnew_busy())
        if not dgsinfo['newraid'].get(data['redundancy']):
            return jsonify({
                'response': 'error',
                'message': 'No eligible data disks are available for this configuration'
            }), 400

        if data['useable'] not in dgsinfo['newraid'][data['redundancy']]:
            keys = list(dgsinfo['newraid'][data['redundancy']].keys())
            keys.append(float(data['useable']))
            keys.sort()
            diskindx = keys.index(float(data['useable'])) + 1
            if diskindx == len(keys):
                diskindx = len(keys) - 2
            data['useable'] = keys[diskindx]

        disks = dgsinfo['newraid'][data['redundancy']][data['useable']]

        if 'single' in data['redundancy']:
            selecteddisks = [disk for disk in disks if disk not in manual_cache][:1]
        elif 'raid10' in data['redundancy']:
            bestdisks = selectraid10(leaderip, disks, freedisks, '', excluded_disks)
            if len(bestdisks) < 1:
                return jsonify({
                    'response': 'error',
                    'message': 'No eligible data disks are available for this configuration'
                }), 400
            selecteddisks = bestdisks.split(',')
        elif 'raid50' in data['redundancy']:
            bestdisks = selectraid50(leaderip, disks, freedisks, '', excluded_disks)
            if len(bestdisks) < 1:
                return jsonify({
                    'response': 'error',
                    'message': 'No eligible data disks are available for this configuration'
                }), 400
            selecteddisks = bestdisks.split(',')
        elif 'raid60' in data['redundancy']:
            bestdisks = selectraid60(leaderip, disks, freedisks, '', excluded_disks)
            if len(bestdisks) < 1:
                return jsonify({
                    'response': 'error',
                    'message': 'No eligible data disks are available for this configuration'
                }), 400
            selecteddisks = bestdisks.split(',')
        else:
            bestdisks = selectdisks(leaderip, disks, freedisks, '', excluded_disks)
            if len(bestdisks) < 1:
                return jsonify({
                    'response': 'error',
                    'message': 'No eligible data disks are available for this configuration'
                }), 400
            selecteddisks = bestdisks.split(',')

    if not selecteddisks:
        return jsonify({
            'response': 'error',
            'message': 'No eligible data disks are available for this configuration'
        }), 400

    # QC 637 (QX-038 step 4, verdict-6155): every disk of a new pool must be known and FREE (pool 'pree') in the fresh allinfo.
    # DGsetPool runs "zpool create -f", and a disk that is a live leg of a pool imported on ANOTHER node is not seen as in use by
    # the owner's local zpool, so without this check the create overwrote that leg (data loss). Also refuse a disk named twice.
    for dsk in selecteddisks:
        if dsk not in allinfo['disks']:
            return _err('disk not found: '+str(dsk)[-12:])
        if allinfo['disks'][dsk].get('pool', 'pree') != 'pree':
            return _err('disk is not free: '+str(dsk)[-12:]+' is in pool '+str(allinfo['disks'][dsk].get('pool')))
    if len(set(selecteddisks)) != len(selecteddisks):
        return _err('a disk is listed more than once')

    diskstring = ''
    for dsk in selecteddisks:
        diskstring += dsk+":"+dsk[-5:]+" "

    data['owner'] = allinfo['disks'][selecteddisks[0]]['host']
    ownerip = allinfo['hosts'][data['owner']]['ipaddress']

    cachestring = ''
    if str(data.get('cache_bool')).lower() == 'true':

        if manual_cache and isinstance(manual_cache, list) and len(manual_cache) > 0:
            cachestring = "cache "
            for dsk in manual_cache:
                cachestring += dsk+":"+dsk[-5:]+" "

        else:
            cache_candidates = []
            if 'raids' in allinfo:
                for raid_data in allinfo['raids'].values():
                    if raid_data.get('status') == 'cache':
                         for d in raid_data.get('disks', []):
                             disk_info = allinfo['disks'].get(d)
                             if disk_info and disk_info.get('host') == data['owner']:
                                 cache_candidates.append(d)

            available_cache = [d for d in cache_candidates if d not in selecteddisks]
            if available_cache:
                cid = available_cache[0]
                cachestring = "cache " + cid + ":" + cid[-5:] + " "
            else:
                print(f"LOG: Cache requested for host {data['owner']}, but no matching disks found in Spare Cache List.")

    print('#############################3')
    print(';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;')
    print(selecteddisks)
    print('#########################333')

    data['owner'] = allinfo['disks'][selecteddisks[0]]['host']
    ownerip = allinfo['hosts'][data['owner']]['ipaddress']

    if 'single' in data['redundancy']:
        datastr = 'Single '+data['user']+' '+data['owner']+" "+selecteddisks[0]+" "+selecteddisks[0][-5:]+" "+cachestring+" "+" nopool "+data['user']+" "+data['owner']
    elif 'mirror' in data['redundancy']:
        datastr = 'mirror '+data['user']+' '+data['owner']+" "+diskstring+" "+cachestring+" "+"nopool "+data['user']+" "+data['owner']
    elif 'volset' in data['redundancy']:
        datastr = 'stripeset '+data['user']+' '+data['owner']+" "+diskstring+" "+cachestring+" nopool "+data['user']+" "+data['owner']
    elif 'raid5' in data['redundancy'] and 'raid50' not in data['redundancy']:     # see addtopool: raid50 must not be taken for raid5
        datastr = 'parity '+data['user']+' '+data['owner']+" "+diskstring+" "+cachestring+" nopool "+data['user']+" "+data['owner']
    elif 'raid6plus' in data['redundancy']:
        datastr = 'parity3 '+data['user']+' '+data['owner']+" "+diskstring+" "+cachestring+" nopool "+data['user']+" "+data['owner']
    elif 'raid10' in data['redundancy']:
        datastr = 'raid10 '+data['user']+' '+data['owner']+" "+diskstring+" "+cachestring+" nopool "+data['user']+" "+data['owner']
    elif 'raid50' in data['redundancy']:
        datastr = 'raid50w'+str(raidwidthof('raid50',selecteddisks,allinfo['disks']))+' '+data['user']+' '+data['owner']+" "+diskstring+" "+cachestring+" nopool "+data['user']+" "+data['owner']
    elif 'raid60' in data['redundancy']:
        datastr = 'raid60w'+str(raidwidthof('raid60',selecteddisks,allinfo['disks']))+' '+data['user']+' '+data['owner']+" "+diskstring+" "+cachestring+" nopool "+data['user']+" "+data['owner']
    elif 'raid6' in data['redundancy']:
        datastr = 'parity2 '+data['user']+' '+data['owner']+" "+diskstring+" "+cachestring+" nopool "+data['user']+" "+data['owner']

    cmndstring = '/TopStor/DGsetPool '+leaderip+' '+datastr+' '+data['user']
    if postchange(cmndstring, data['owner']) == 'queued':
        _poolnew_queued(selecteddisks)

    return jsonify(data)

@app.route('/api/v1/pools/updatecache', methods=['GET','POST'])
@login_required
@audit_command
def dgsupdatecache(data):
    global allinfo, myhost, leaderip

    if 'baduser' in data['response']:
        return {'response': 'baduser'}

    getalltime('yes')

    pool = data.get('pool')
    if not pool or pool not in allinfo['pools']:
        return jsonify({'response': 'error', 'message': 'Pool not found'}), 400

    pool_data = allinfo['pools'][pool]
    old_cache_disks = []
    for raidId in pool_data.get('raids', []):
        if raidId.split('_')[0] == 'cache':
            old_cache_disks.extend(allinfo['raids'].get(raidId, {}).get('disks', []))

    data['owner'] = pool_data['host']

    new_cache = data.get('cache')
    if not isinstance(new_cache, list):
        new_cache = [new_cache] if new_cache else []

    if not new_cache:
        # QSD5.351 (QC 631 i2): the same choice as fixcachelocality.py after a take-over: a spare cache disk of the
        # owner (etcd cachespares), else a free disk of the owner smaller than the pool's data disks, else the old
        # rule (a free disk smaller than the rest of the owner's free disks).
        from fixcachelocality import pick_cache_disk, spare_list
        pick, why = pick_cache_disk(allinfo, data['owner'], pool, old_cache_disks, spare_list(leaderip))
        if pick:
            new_cache = [pick]

    if not new_cache:
        return jsonify({
            'response': 'error',
            'message': f'No spare cache disk on {data["owner"]}, and no disk on {data["owner"]} is smaller than the rest (or than the pool data disks) to use as cache'
        }), 400

    new_cache = [d for d in new_cache if d not in old_cache_disks]
    if not new_cache:
        return jsonify({
            'response': 'error',
            'message': 'Selected disk is already this pool\'s cache'
        }), 400

    ownerip = allinfo['hosts'][data['owner']]['ipaddress']

    oldstring = ''
    for dsk in old_cache_disks:
        oldstring += dsk+":"+dsk[-5:]+" "
    newstring = ''
    for dsk in new_cache:
        newstring += dsk+":"+dsk[-5:]+" "

    datastr = 'updatecache '+data['user']+' '+data['owner']+' '+pool+' old '+oldstring+'new '+newstring+'nopool'
    cmndstring = '/TopStor/DGsetPool '+leaderip+' '+datastr+' '+data['user']
    postchange(cmndstring, data['owner'])

    return jsonify(data)

@app.route('/api/v1/volumes/stats', methods=['GET','POST'])
@login_required
@audit_command
def volumestats(data):
 global allinfo 
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 getalltime()
 volstats = allvolstats(leaderip, deepcopy(allinfo))
 return jsonify(volstats)

@app.route('/api/v1/volumes/volumelist', methods=['GET','POST'])
@login_required
@audit_command
def volumeslist(data):
 global allinfo 
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 getalltime()
 volumes = []
 vid = 0
 for vol in allinfo['volumes']:
  volumes.append({'id':vid, 'text':vol.split('_')[0], 'fullname':vol,'pool':allinfo['volumes'][vol]['pool']})
  vid += 1
 return jsonify(volumes)

@app.route('/api/v1/tenants/tenantinfo', methods=['GET','POST'])
@login_required
@audit_command
def tenantsinfo(data):
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 alltenants = gettenants()
 alltenants.append({'id':len(allpools), 'text':'Cluster'})
 return jsonify({'results':alltenants})



@app.route('/api/v1/volumes/poolsinfo', methods=['GET','POST'])
@login_required
@audit_command
def volpoolsinfo(data):
 global allpools
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 allpools = getpools()
 return jsonify({'results':allpools})


@app.route('/api/v1/volumes/snapshots/snapshotsinfo', methods=['GET','POST'])
@login_required
@audit_command
def volumessnapshotsinfo(data):
 global allvolumes, alldsks, allinfo
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 snaplist = {'Once':[], 'Minutely': [], 'Hourly': [], 'Weekly':[], '-':[]}
 periodlist = {'Minutely': [], 'Hourly': [], 'Weekly':[], 'Trend': []}
 getalltime()
 allgroups = getgroups()
 alllist = []
 snappriods = []
 for snap in allinfo['snapshots']:
  allinfo['snapshots'][snap]['date'] = datetime.strptime(allinfo['snapshots'][snap]['creation'], '%a %b %d %Y').strftime('%d-%B-%Y')
  print('#####################################33')
  print(allinfo['snapshots'][snap])
  print('#####################################33')
  snaplist[allinfo['snapshots'][snap]['snaptype']].append(allinfo['snapshots'][snap].copy())
  alllist.append(allinfo['snapshots'][snap].copy())
 for period in allinfo['snapperiods']:
  snappriods.append(allinfo['snapperiods'][period].copy())
  periodlist[allinfo['snapperiods'][period]['periodtype']].append(allinfo['snapperiods'][period].copy())
 return jsonify({'allsnaps':alllist, 'Once':snaplist['Once'], 'Hourly':snaplist['Hourly'], 'Weekly':snaplist['Weekly'], 'Minutely':snaplist['Minutely'] ,'allperiods':snappriods, 'Minutelyperiod':periodlist['Minutely'], 'Hourlyperiod':periodlist['Hourly'], 'Weeklyperiod':periodlist['Weekly']})

def volumesinfo(prot='all'):
 global allvolumes, alldsks, allinfo
 getalltime()
 allgroups = getgroups()
 volgrouplist = []
 volumes = []
 if prot == 'all':
   prot = 'S'
   prot2 = 'H'
 else:
  prot2 = prot
 for volume in allinfo['volumes']:
  if prot in allinfo['volumes'][volume]['prot'] or prot2 in allinfo['volumes'][volume]['prot']:
   volgrps = []
   if prot in ['CIFS','NFS']:
    print('##################')
    print(allinfo['volumes'][volume])
    print('##################')
    try:
        volgrouplist =  deepcopy(allinfo['volumes'][volume]['groups'])
    except:
        volgrouplist=[]
    if type(volgrouplist) != list:
      volgrouplist = volgrouplist.split(',')
    for group in allgroups:
     if group[0] in volgrouplist:
      volgrps.append(group[1])
   volumes.append(deepcopy(allinfo['volumes'][volume]))
   volumes[-1]['groups'] = deepcopy(volgrps)
   if 'chappas' in volumes[-1]:   # the iSCSI CHAP secret is in no answer (test 653 QX-054)
    volumes[-1]['chappas'] = chap_shown(volumes[-1]['chappas'])
 return volumes


@app.route('/api/v1/volumes/CIFS/volumesinfo', methods=['GET','POST'])
@login_required
@audit_command
def volumescifsinfo(data):
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 volumes = volumesinfo('CIFS') 
 return jsonify({'allvolumes':volumes})

@app.route('/api/v1/volumes/ISCSI/volumesinfo', methods=['GET','POST'])
@login_required
@audit_command
def volumesiscsiinfo(data):
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 volumes = volumesinfo('ISCSI') 
 return jsonify({'allvolumes':volumes})

@app.route('/api/v1/volumes/NFS/volumesinfo', methods=['GET','POST'])
@login_required
@audit_command
def volumesnfsinfo(data):
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 volumes = volumesinfo('NFS') 
 return jsonify({'allvolumes':volumes})

@app.route('/api/v1/volumes/HOME/volumesinfo', methods=['GET','POST'])
@login_required
@audit_command
def volumeshomeinfo(data):
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 volumes = volumesinfo('HOME') 
 return jsonify({'allvolumes':volumes})

@app.route('/api/v1/volumes/S3/volumesinfo', methods=['GET','POST'])
@login_required
@audit_command
def volumess3info(data):
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 volumes = volumesinfo('S3')   # volumes whose prot is S3 in the cluster info; an empty list when there are none
 return jsonify({'allvolumes':volumes})

@app.route('/api/v1/volumes/volumesinfo', methods=['GET','POST'])
@login_required
@audit_command
def volumesallinfo(data):
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 volumes = volumesinfo() 
 return jsonify({'allvolumes':volumes})



@app.route('/api/v1/pools/poolsinfo', methods=['GET','POST'])
@login_required
@audit_command
def poolsinfo(data):
 global allpools
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 allpools = getpools()
 allpools.append({'id':len(allpools), 'text':'-------'})
 return jsonify({'results':allpools})

def _users_for_ids():
 # QC 609: the user ids a client sends (the 'id' of users/userlist = position in usersinfo) were resolved against the module
 # global allusers, which only a previous users/userlist call fills (empty after a restart, stale after a change).  Read the
 # users again: same order as users/userlist, so the ids mean the same.  Falls back to the global when etcd does not answer.
 try:
  names = [u['name'].replace('usersinfo/','') for u in etcdgetjson(leaderip,'usersinfo','--prefix')]
  return [{'id': i, 'name': n} for i, n in enumerate(names)]
 except Exception:
  return allusers

@app.route('/api/v1/groups/groupchange', methods=['GET','POST'])
@login_required
@audit_command
def pgroupchange(data):
 global leaderip
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 if data.get('name') == EVERYONE:
  data['error'] = 'everyonefixed'     # all users are always members of Everyone: nobody changes it
  return data
 usrs = data.get('users') or ''
 usrstr = ''
 if len(usrs) < 1:
  usrstr = 'NoUser'
 else:
  _ulist = _users_for_ids()
  for usr in usrs.split(','):
   for suser in _ulist:
    if (str(suser['id']) == str(usr) or suser['name'] == str(usr)) and suser['name'] not in usrstr.split(','):
     usrstr += suser['name']+','
  usrstr = usrstr[:-1]
  if usrstr == '':
   usrstr = 'NoUser'
 cmndstring = '/TopStor/UnixChangeGroup '+leaderip+' '+' '+data.get('name')+' users'+usrstr+' '+data['user']+' '+'change'
 postchange(cmndstring)
 return data

@app.route('/api/v1/replication/addpartner', methods=['GET','POST'])
@login_required
@audit_command
def partneradd(data):
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 cmndstring = '/TopStor/PartnerAdd.py '+data.get('partnerip')+' '+data.get('partneralias')+' '+data.get('replitype')+' '+data.get('repliport')+' '+data.get('phrase')+' '+data.get('user')
 postchange(cmndstring)
 return data

@app.route('/api/v1/users/userchange', methods=['GET','POST'])
@login_required
@audit_command
def userchange(data):
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 grps = data.get('groups')
 groupstr = ''
 if 'Cluster' not in data['tenant']:
     # QSD5.352 r5 (validator N4): the NFS tenant path (TenantChangeUser: group change + NFS container restart) had no privilege
     # check at all (the Cluster path goes to UnixChangeUser, which checks Box_Users).  Same privilege, Priv1004 + noprivilege.
     if not has_privilege('Box_Users', data.get('user')):
        logmsg.sendlog('Priv1004','error','system',str(data.get('user')))
        return {'response': data.get('response'), 'error': 'noprivilege'}
     volinfo = get('vol',data['tenant'])[0]
     data['owner'] = 'leader'
     if 'NFS' not in str(volinfo[0]):     # r5: a tenant that is no NFS volume raised NameError (pool), HTTP 500
        return {'response': data.get('response'), 'error': 'notnfs'}
     if 'NFS' in volinfo[0]:
        data['owner'] = volinfo[0].split('/')[2]
        pool = volinfo[0].split('/')[3]
        if len(grps) < 3:
            grps = 'NoGroup'
     cmndstring = '/TopStor/TenantChangeUser '+leaderip+' '+data['name']+' groups'+grps+' '+pool+' '+data['tenant']+' '+data['response']
     postchange(cmndstring,data['owner'])
     return data
 groupstr, bad = resolve_groups(grps, getgroups())
 if bad:
  # a clear refusal (HTTP 400, so the UI queue counts it as failed) instead of an unhandled exception and HTTP 500
  data['response'] = 'error'
  data['error'] = 'invalid group: '+','.join(bad)
  return jsonify(data), 400
 groupstr = with_everyone(groupstr)
 cmndstring = '/TopStor/UnixChangeUser '+leaderip+' '+data.get('name')+' groups'+groupstr+' '+data['user']+' '+'change'
 postchange(cmndstring)
 return data


 
@app.route('/api/v1/info/onedaylog', methods=['GET','POST'])
@login_required
@audit_command
def getonedaylog(data):
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 result = onedaylog() 
 return result 
@app.route('/api/v1/info/logs', methods=['GET','POST'])
@login_required
@audit_command
def getalllogs(data):
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 notif = getlogs()
 return jsonify({'alllogs': notif})

@app.route('/api/v1/info/commandlog', methods=['GET','POST'])
@login_required
@audit_command
def getcommandlog(data):
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 commands = get_command_log(data['user'])
 return jsonify({'response': 'Ok', 'commands': commands})


@app.route('/api/v1/login/renewtoken', methods=['GET','POST'])
@login_required
@audit_command
def renewtoken(data):
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 user = loggedusers[data['token']]['user']
 setlogin(leaderip,myhost, user,'!',data['token'])
 return data


@app.route('/api/v1/info/cversion', methods=['GET','POST'])
@login_required
@audit_command
def getcversion(data):
    global leaderip, leader, myhost
    if 'baduser' in data['response']:
      return {'response': 'baduser'}
    #cmdline='/TopStor/getcversion.sh '+leaderip+' '+leader+' '+myhost
    #subprocess.run(cmdline,stdout=subprocess.PIPE)
    #postchange(cmdline)
    cversions = get('cversion/'+myhost)[0]
    return { 'response':'Ok', 'cversion': str(cversions)}



@app.route('/api/v1/info/notification', methods=['GET','POST'])
@login_required
@audit_command
def getnotification(data):
 global leaderip, myhost
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 notifbody = get('notification')[0].split(' ')[1:]
 isinsync = get('isinsync')[0]
 with open('/root/tmptmp','a') as f:
    f.write(str(notifbody))
 requests = get('request','--prefix')
 requestdict = {}
 for req in requests:
  reqname = req[0].split('/')[1]
  reqhost = req[0].split('/')[2]
  reqstatus = req[1]
  if reqname not in requestdict:
   requestdict[reqname] = {}
  requestdict[reqname][reqhost] = reqstatus
 try:
    msg = logdict[notifbody[3]]
 except:
    msg = logdict['NotSupported']
    logmsg.sendlog('NotSupported','warning','system',str(notifbody))
    return { 'isinsync': isinsync, 'response': 'Ok' }
    
   
 msgbody = '.'
 notifc = 6
 for word in msg[4:]:
  if word == r'\:':
   # an escaped colon in msgsglobal.txt is a literal ':' in the text, not a placeholder (e.g. Priv1004)
   msgbody = msgbody[:-1]+' :.'
  elif word == ':':
   try:
    msgbody = msgbody[:-1]+' '+notifbody[notifc]+'.'
   except:
    msgbody = str(msgbody) +' '+str(notifbody)+'parseerror.'
    with open('/root/fapierror','w') as f:
     f.write(msgbody+'\n'+str(msg))
    print('notification parse error')
    print('############################')
   notifc += 1
  elif len(word) > 0:
   msgbody = msgbody[:-1]+' '+word+'.' 
 notif = { 'isinsync': isinsync, 'importance':msg[0].replace(':',''), 'msgcode': notifbody[3], 'date':notifbody[0], 'time':notifbody[1],
	 'host':notifbody[2], 'type':notifbody[4], 'user': notifbody[5], 'msgbody': msgbody[1:],'requests':requestdict, 'response':'Ok'}
 return jsonify(notif)

# QSD5.348 (test 663 QX-064): volumes/snapshots/create had no parameter check: a missing key, an unknown snapsel or owner was a
# KeyError (HTTP 500 "internal error"), a bad Once name or a bad every/keep went on to the scripts (which clamp 0/-1/abc to 1).
# snapcreate_guard() checks the call against the leader's cached info (allinfo) before anything is queued; it returns the
# refusal text or None. Only the keys of the chosen snapsel are checked; extra keys stay accepted.
SNAPCREATE_KEYS = {'Once': ['pool', 'volume', 'name'], 'Minutely': ['pool', 'volume', 'every', 'keep'],
                   'Hourly': ['pool', 'volume', 'sminute', 'every', 'keep'], 'Weekly': ['pool', 'volume', 'stime', 'every', 'keep']}
SNAPCREATE_NAME = re.compile(r'^[A-Za-z0-9_][A-Za-z0-9_.:-]{0,63}$')
SNAPCREATE_DAYS = ('sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat')

def snapcreate_guard(data, info):
 def missing(key):
  return str(data.get(key, '')) == ''
 def whole(key, low, high=None):
  value = str(data[key])
  if not re.match(r'^[0-9]{1,9}$', value):
   return False
  return int(value) >= low and (high is None or int(value) <= high)
 for key in ('snapsel', 'owner'):
  if missing(key):
   return 'missing parameter: '+key
 snapsel = data['snapsel']
 if snapsel not in SNAPCREATE_KEYS:
  return 'invalid parameter: snapsel (Once, Minutely, Hourly, Weekly)'
 for key in SNAPCREATE_KEYS[snapsel]:
  if missing(key):
   return 'missing parameter: '+key
 if data['owner'] not in info.get('hosts', {}):
  return 'no such node: '+data['owner']
 if data['pool'] not in info.get('pools', {}):
  return 'no such pool: '+data['pool']
 volume = info.get('volumes', {}).get(data['volume'])
 if not isinstance(volume, dict) or volume.get('pool') != data['pool']:
  return 'no such volume: '+data['volume']
 if snapsel == 'Once':
  if not SNAPCREATE_NAME.match(data['name']):
   return 'invalid character in parameter: name'
  return None
 if snapsel == 'Hourly' and not whole('sminute', 0, 59):
  return 'invalid parameter: sminute'
 if snapsel == 'Weekly':
  stime = re.match(r'^([0-9]{1,2}):([0-9]{2})$', str(data['stime']))
  if not stime or int(stime.group(1)) > 23 or int(stime.group(2)) > 59:
   return 'invalid parameter: stime'
  # for Weekly 'every' is the day of the week (the UI sends its sday, e.g. Sat): the cron day-of-week field
  if str(data['every']).lower() not in SNAPCREATE_DAYS and not whole('every', 0, 7):
   return 'invalid parameter: every'
 elif not whole('every', 1):
  return 'parameter must be a positive number: every'
 if not whole('keep', 1):
  return 'parameter must be a positive number: keep'
 return None

@app.route('/api/v1/volumes/snapshots/create', methods=['GET','POST'])
@login_required
@audit_command
def volumesnapshotscreate(data):
 global allinfo, myhost
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 datastr = ''
 getalltime()
 refusal = snapcreate_guard(data, allinfo)
 if refusal:
  return jsonify({'response': 'error', 'message': refusal}), 400
 ownerip = allinfo['hosts'][data['owner']]['ipaddress']
 data['leaderip'] = leaderip
 # QSD5.345 (test 660 QX-061 step 5): a Once snapshot is stored as <name>.<epoch>, so a repeated name on the same volume
 # made a second snapshot; refuse it here (nothing queued). The same name on another volume is allowed.
 if data['snapsel'] == 'Once':
  for snap in allinfo['snapshots'].values():
   if snap.get('fullname','').split('@')[0] != data['pool']+'/'+data['volume']:
    continue
   base = snap.get('name','')
   if '.' in base and base.rsplit('.',1)[1].isdigit():
    base = base.rsplit('.',1)[0]
   if base == data.get('name'):
    return jsonify({'response': 'error', 'error': 'snapexists',
                    'message': 'Snapshot name already exists on volume '+data['volume']+': '+data['name']}), 400
 switch = { 'Once':['snapsel','leaderip', 'name','pool','volume'], 'Minutely':['snapsel', 'leaderip', 'pool', 'volume', 'every', 'keep'],
	'Hourly':['snapsel', 'leaderip', 'pool', 'volume', 'sminute', 'every', 'keep'], 
	'Weekly':['snapsel', 'leaderip', 'pool', 'volume', 'stime', 'every', 'keep'] }
 datastr = ''
 for param in switch[data['snapsel']]:
  datastr +=data[param]+' '
 #datastr = data['name']+' '+data['pool']+' '+data['volume']+' '+data['user']
 if 'receiver' not in data:
   datastr += 'NoReceiver'
 else:
   datastr += data['receiver']
 print('#############################')
 print(logsafe(data))
 print(mask_text(datastr, _request_secrets(data)))
 print('###########################')
 cmndstring = '/TopStor/SnapshotCreate'+datastr+' '+data['user']
 postchange(cmndstring,data['owner'])
# z= cmndstring.split(' ')
# msg={'req': 'Pumpthis', 'reply':z}
# sendhost(ownerip, str(msg),'recvreply',myhost)
 return data


# iSCSI CHAP (QSD5.341, test 653 QX-054): volumes/create and volumes/config replaced the request's chapuser/chappas with one
# built-in pair, the same on every installation, and returned it in the answer; the scripts set it on the TPG only, with
# authentication=0, so CHAP was never asked. Now the requested pair is checked here (HTTP 400, nothing queued, when bad), the
# secret goes on encrypted (encthis.sh, as the CIFS domain password; the clear secret is decrypted only by
# /pace/iscsichap.sh, which writes it to the node ACLs in configfs) and no answer, trace or command log carries it.
# 'nochap' = no CHAP (no chapuser/chappas in the request); 'clearchap' (volumes/config chapuser=nochap) removes it.
CHAP_NONE = 'nochap'
CHAP_CLEAR = 'clearchap'
CHAP_SECRETS = ('chappas',)     # request keys never echoed nor written to cmdaudit.log
_CHAPUSER_CHARS = re.compile(r'[A-Za-z0-9._:-]*')      # fullmatch: '$' would let a final newline in
_CHAPPAS_CHARS = re.compile(r'[A-Za-z0-9._:@!-]*')

def chap_raw(data, key):
 # the value as it was sent: login_required removes blanks, so a secret with a blank must be refused, not shortened
 val = request.args.get(key)
 if val is None:
  val = data.get(key)
 return None if val is None else str(val)

def chap_check(user, secret):
 # None when good, else the message of the HTTP 400 (it never contains the secret)
 if user is not None:
  if not _CHAPUSER_CHARS.fullmatch(user):
   return 'invalid character in chapuser: use letters, digits and . _ : - (1 to 64 characters); nothing changed'
  if not 1 <= len(user) <= 64:
   return 'chapuser must be 1 to 64 characters (letters, digits and . _ : -); nothing changed'
 if secret is not None:
  if not _CHAPPAS_CHARS.fullmatch(secret):
   return 'invalid character in chappas: use letters, digits and . _ : @ ! - (12 to 16 characters); nothing changed'
  if not 12 <= len(secret) <= 16:
   return 'chappas must be 12 to 16 characters (letters, digits and . _ : @ ! -); nothing changed'
 return None

def chap_encrypt(user, secret):
 # the secret on stdin, not on the command line (ps, the cmdaudit command list); '/' cannot be in a '/' separated record
 try:
  out = subprocess.run(['/TopStor/encthis.sh', user, '-'], input=(secret+'\n').encode(), stdout=subprocess.PIPE,
                       stderr=subprocess.DEVNULL).stdout.decode()
  enc = out.split('_result')[1].strip()
 except Exception:
  return None
 if not enc or not re.fullmatch(r'[A-Za-z0-9+/=]+', enc):
  return None
 return 'chapenc_'+enc.replace('/','@@sep')

def chap_refuse(message, err='invalidchap'):
 return jsonify({'response': 'error', 'error': err, 'message': message}), 400

def chap_hide(data):
 for k in CHAP_SECRETS:
  if k in data:
   data[k] = '***'

def chap_shown(token):
 # what an answer shows of a stored secret
 return '' if str(token) in ('', CHAP_NONE, CHAP_CLEAR, 'None') else '***'

# (chapuser, chappas token) for volumes/create, or (None, message) when refused
def chap_create(data):
 user, secret = chap_raw(data, 'chapuser'), chap_raw(data, 'chappas')
 if user == '':
  user = None
 if secret == '':
  secret = None
 if user == CHAP_NONE and secret is None:
  user = None
 if user is None and secret is None:
  return CHAP_NONE, CHAP_NONE
 msg = chap_check(user, secret)
 if msg:
  return None, msg
 if user is None or secret is None or user == CHAP_NONE:
  return None, 'chapuser and chappas are given together (or neither, for no CHAP); nothing changed'
 token = chap_encrypt(user, secret)
 if token is None:
  return None, 'the CHAP secret could not be stored; nothing changed'
 return user, token

# the same for volumes/config: what is not sent stays as it is; chapuser=nochap removes CHAP
def chap_config(data, volume):
 curuser, curtoken = str(volume.get('chapuser', CHAP_NONE)), str(volume.get('chappas', CHAP_NONE))
 user, secret = chap_raw(data, 'chapuser'), chap_raw(data, 'chappas')
 if user == '':
  user = None
 if secret == '':
  secret = None
 if user is None and secret is None:
  return curuser, curtoken
 if user == CHAP_NONE and secret is None:
  return CHAP_NONE, CHAP_CLEAR
 msg = chap_check(user, secret)
 if msg:
  return None, msg
 if user == CHAP_NONE:
  return None, 'chapuser=nochap removes CHAP and takes no chappas; nothing changed'
 if secret is None:
  if user == curuser and curtoken.startswith('chapenc_'):
   return curuser, curtoken
  return None, 'a new chapuser needs its chappas; nothing changed'
 if user is None:
  if curuser in ('', CHAP_NONE, 'None') or chap_check(curuser, None):
   return None, 'chappas needs a chapuser (the volume has none); nothing changed'
  user = curuser
 token = chap_encrypt(user, secret)
 if token is None:
  return None, 'the CHAP secret could not be stored; nothing changed'
 return user, token



# the volume types that have a /TopStor/VolumeCreate<type> script
VOLCREATE_TYPES = ('CIFS', 'CIFSdom', 'HOME', 'ISCSI', 'NFS', 'NFS_non_container')

@app.route('/api/v1/volumes/create', methods=['GET','POST'])
@login_required
@audit_command
def volumecreate(data):
 global allinfo, myhost
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 # only a type with a /TopStor/VolumeCreate<type> script: S3 (no backend) and unknown types were queued as a command
 # that does not exist and answered 200 as accepted; now HTTP 400, nothing read, created or queued (test 657 QX-058 step 4)
 voltype = str(data.get('type', ''))
 if voltype == 'S3':
  return jsonify({'response': 'error', 'error': 'nos3backend', 'message': 'Failed to create S3 bucket volume'}), 400
 if voltype not in VOLCREATE_TYPES:
  return jsonify({'response': 'error', 'error': 'badtype', 'message': 'Failed to create volume: unknown volume type '+voltype}), 400
 datastr = ''
 # the name as it was sent (login_required removes blanks, so 'q 1' would pass as 'q1'): volvalid.py, HTTP 400 and
 # nothing queued for a name the scripts cannot carry (test 647 QX-048 step 2)
 rawname = request.args.get('name', data.get('name'))
 code, reason = check_volname_coded(rawname)
 if reason:
  logmsg.sendlog(code,'error',data.get('user','system'),vollogname(rawname))
  return jsonify({'response': 'error', 'error': 'invalidname', 'name': vollogname(rawname), 'message': reason}), 400
 # iSCSI CHAP: checked before anything is done; the secret is kept only encrypted (chaptoken), no answer shows it
 if 'ISCSI' in str(data.get('type', '')):
  chapuser, chaptoken = chap_create(data)
  chap_hide(data)
  if chapuser is None:
   return chap_refuse(chaptoken)
 else:
  chap_hide(data)
 datatype = ip_context(data['type'], data.get('domname',''))
 ishome = 'HOME' in str(data.get('type', ''))
 if ishome:
  # QSD5.352 r9 (prover D4): the Home Folders page sent active=Yes; VolumeCreateHOME wrote 'Yes' as the share's status and
  # the home was never served.  A home is created 'active' (also for yes / no value) or 'disabled'; other words: refused.
  act = str(data.get('active', 'active')).strip().lower()
  if act in ('', 'active', 'yes'):
   data['active'] = 'active'
  elif act in ('disabled', 'disable', 'no'):
   data['active'] = 'disabled'
  else:
   return {'response': data.get('response'), 'error': 'invalidstatus'}
 if ishome:   # merge: M's test ('HOME' in type), A's check of the user
  # a home is named after its user (VolumeCreateHOME takes the name as the user): it must be an existing user without a
  # home, not a name no user has (is_unique_name refused every home, test 655 QX-056 step 2); nothing queued when refused
  homeerr, homemsg, homepool = home_user_check(rawname)
  if homeerr == 'hashome':
   logmsg.sendlog('Unlin1028','warning',data.get('user','system'),vollogname(rawname),homepool or 'unknown')
  elif homeerr:
   logmsg.sendlog('Unlin1029','error',data.get('user','system'),vollogname(rawname))
  if homeerr:
   return jsonify({'response': 'error', 'error': homeerr, 'name': vollogname(rawname), 'message': homemsg}), 400
  nameuq = 0
 else:
  nameuq = int(is_unique_name(data['name'], vols=False))
 isvu =  int(is_valid_ip(data['ipaddress']))+int(is_unique_ip(data['ipaddress'],datatype))+nameuq
 if isvu == 0:
    print('ip is valid')
 else:
    # refused: HTTP 400 with the reason (it answered 200 with the echoed request, only the log said why)
    # is_valid_ip gives 10, is_unique_ip 100, is_unique_name 1000
    if isvu % 100 >= 10:
        logmsg.sendlog('IPaddrfa','error','system',data.get('user','system'))
        err, msg = 'invalidip', 'invalid IP address in the request: '+str(data['ipaddress'])
    elif isvu % 1000 >= 100:
        logmsg.sendlog('IPadduqfa','error','system',data.get('user','system'))
        err, msg = 'ipinuse', 'the IP address is already in use: '+str(data['ipaddress'])
    else:
        logmsg.sendlog('IPnamuqfa','error','system',data.get('user','system'))
        err, msg = 'nameinuse', 'the name is already in use by a user or a group: '+str(data['name'])
    return jsonify({'response': 'error', 'error': err, 'message': msg}), 400
 getalltime()
 if data.get('pool') not in allinfo['pools']:
  # no pool chosen / unknown pool: a clean answer instead of a KeyError (HTTP 500)
  logmsg.sendlog('Volpool1','error',loggedusers[data['token']]['user'],str(data.get('name','')))
  data['error'] = 'nopool'
  return data
 ownerip = allinfo['hosts'][allinfo['pools'][data['pool']]['host']]['ipaddress']
 data['owner'] = allinfo['hosts'][allinfo['pools'][data['pool']]['host']]['name']
 if 'groups' in data:
  grps = share_groups(data['groups'])
  if grps is None:
   data['error'] = 'invalidgroup'
   return data
  data['groups'] = only_everyone(grps)
 chapmask = None
 if 'ISCSI' in data['type']:
  # the requested CHAP (or none): it was replaced here by one built-in pair for every LUN (test 653 QX-054 step 1)
  data['chapuser'] = chapuser
  if chaptoken != CHAP_NONE:
   data['chappas'] = '***'
   chapmask = chaptoken
  datastr = data['pool']+' '+data['name']+' '+data['size']+' '+data['ipaddress']+' '+data['Subnet']+' '+data['portalport']+' '+data['initiators']+' '+chapuser+' '+chaptoken+' '+data['active']+' '+data['user']+' '+data['owner']+' '+data['user']
 elif 'CIFSdom' in data['type']:

  cmdline=['/TopStor/encthis.sh',data["domname"],data["dompass"]]
  data["dompass"]=subprocess.run(cmdline,stdout=subprocess.PIPE).stdout.decode().split('_result')[1].replace('/','@@sep')

  # Call resolve script if domsrv is passed and domip is not
  if data['domsrv']:
    cmdline = ['/TopStor/resolve_dns.sh', leaderip, data['domsrv']]
    result = subprocess.run(cmdline, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    output = result.stdout.decode().strip()

    resolved_ip = ""
    if output.startswith("RESOLVEDIP="):
     resolved_ip = output.split("=")[1]

    if resolved_ip and int(is_valid_ip(resolved_ip)) == 0:
     data['domip'] = resolved_ip
     data['domsrv'] = ''
    else:
     logmsg.sendlog('CIFS1033', 'error', 'system', data['name'],data["domsrv"])
     return data

  datastr = data['pool']+' '+data['name']+' '+data['size']+' '+' '+data['ipaddress']+' '+data['Subnet']+' '+data['active']+' '+data['user']+' '+data['owner']+' '+data['user']+' '+ data["domname"]+' '+ data["domsrv"]+' '+ data["domip"]+' '+ data["domadmin"]+' '+ data["dompass"]

 elif 'NFS' in data['type']:
  datastr = data['pool']+' '+data['name']+' '+data['size']+' '+data['rootname']+' '+data['rootid']+' '+data['groupname']+' '+data['groupid']+' '+data['ipaddress']+' '+data['Subnet']+' '+data['active']+' '+data['user']+' '+data['owner']+' '+data['user']

 else:
  datastr = data['pool']+' '+data['name']+' '+data['size']+' '+data['groups']+' '+data['ipaddress']+' '+data['Subnet']+' '+data['active']+' '+data['user']+' '+data['owner']+' '+data['user']
 print('#############################')
 with open('/TopStordata/volcreate','a') as f:
    f.write(str(masked(data))+'\n'+'owner '+str(data['owner'])+'\n')
 print(logsafe(data))
 print(mask_text(datastr.replace(chapmask, '***') if chapmask else datastr, _request_secrets(data)))
 print('###########################')
 if 'ISCSI' not in data['type']:
  # data efficiency of the new volume: both on unless the request says off (the scripts read these two words anywhere on the line)
  datastr += ' compression='+('off' if str(data.get('compression','on')).lower() in ('off','false','no','0') else 'lz4')
  datastr += ' dedup='+('off' if str(data.get('dedup','on')).lower() in ('off','false','no','0') else 'on')
 cmndstring = '/TopStor/VolumeCreate'+data['type']+' '+leaderip+' '+datastr
 #z= cmndstring.split(' ')
 #msg={'req': 'Pumpthis', 'reply':z}
 #sendhost(ownerip, str(msg),'recvreply',myhost)
 postchange(cmndstring,data['owner'])
 return data

# ---- iSCSI CHAP (QSD5.344, QC test 653) ---------------------------------------------------------------------------------
# volumes/create and volumes/config used to replace chapuser/chappas with one hard-coded pair, and the target never asked
# for CHAP.  Now: no chapuser and no chappas = no CHAP (stored as NoCHAP/NoCHAP); both given = CHAP on every initiator
# ACL of the LUN, the target asks for it (pace/addzfsvolumeastarget.sh).  The secret is stored and passed on encrypted
# ('enc~...', secretmask.phrase_encrypt), only the target script decrypts it.  volumes/config without the two fields keeps
# the stored ones; both sent empty switches CHAP off.
CHAP_NONE = 'NoCHAP'
CHAP_OFF_WORDS = ('nochap', '-', 'null')
CHAP_LEGACY = ('MoatazNegm', 'MezoAdmin')      # the pair of every volume before QSD5.344: never enforced, means no CHAP
CHAP_USER_RE = re.compile(r'^[A-Za-z0-9._:@-]{1,64}$')
CHAP_SECRET_RE = re.compile(r'^[A-Za-z0-9._:+=,~-]{12,64}$')

def iscsi_chap(data, volume=None):
 # returns (chapuser, stored secret, None) or (None, None, error message)
 if 'chapuser' not in data and 'chappas' not in data:
  if volume is not None:
   return str(volume.get('chapuser', CHAP_NONE)), str(volume.get('chappas', CHAP_NONE)), None
  return CHAP_NONE, CHAP_NONE, None
 user, secret = str(data.get('chapuser', '')), str(data.get('chappas', ''))
 try:      # login_required removed every blank: a value typed with a blank is refused, not silently shortened
  for k in ('chapuser', 'chappas'):
   if re.search(r'\s', str(request.values.get(k, ''))):
    return None, None, 'invalid character in parameter: '+k+' (no blanks)'
 except RuntimeError:
  pass
 if user == '' and secret == '':
  return CHAP_NONE, CHAP_NONE, None
 if user == '' or secret == '':
  return None, None, 'chapuser and chappas must be given together'
 # QSD5.344 (validator L1): pace/addzfsvolumeastarget.sh reads NoCHAP, nochap and '-' as 'no CHAP', LIO reads NULL as
 # 'clear': such a user would silently switch CHAP off, so it is refused (any case)
 if user.lower() in CHAP_OFF_WORDS:
  return None, None, 'invalid parameter: chapuser ('+user+' is a reserved word, leave chapuser and chappas out for no CHAP)'
 if not CHAP_USER_RE.match(user):
  return None, None, 'invalid character in parameter: chapuser (1-64 letters, digits, . _ : @ -)'
 if not CHAP_SECRET_RE.match(secret):
  return None, None, 'invalid character in parameter: chappas (12-64 letters, digits, . _ : + = , ~ -)'
 try:
  return user, phrase_encrypt('chap', secret), None
 except Exception:
  return None, None, 'the CHAP secret could not be stored'

def _chap_owner(user, stored):
 # None = no CHAP; else the chap user (the secret is compared only when both sides have the same user)
 user, stored = str(user), str(stored)
 if user.lower() in CHAP_OFF_WORDS or user in ('', '_1') or (user, stored) == CHAP_LEGACY:
  return None
 return user

def iscsi_chap_same_address(volumes, volname, ipaddress, user, stored):
 # QSD5.344 (validator M4): one iSCSI target per address and one ACL per initiator.  A CHAP LUN on an address shared with
 # no-CHAP LUNs switched authentication on for the whole target (their initiators were locked out); two LUNs with
 # different CHAP pairs flipped a shared initiator's ACL (last one wins).  So every iSCSI volume of one address has the
 # same CHAP: all none, or all the same user and secret.  Returns None or the refusal message.
 mine = _chap_owner(user, stored)
 myclear = None
 for name, vol in (volumes or {}).items():
  if name == volname or vol.get('prot') != 'ISCSI' or str(vol.get('ipaddress')) != str(ipaddress):
   continue
  theirs = _chap_owner(vol.get('chapuser', CHAP_NONE), vol.get('chappas', CHAP_NONE))
  if mine is None and theirs is None:
   continue
  if mine == theirs:
   if myclear is None:
    myclear = phrase_decrypt('chap', stored)
   if phrase_decrypt('chap', vol.get('chappas', '')) == myclear:
    continue
   return 'CHAP must be the same for every iSCSI volume on '+str(ipaddress)+': volume '+str(name)+' has another secret for chapuser '+mine
  return 'CHAP must be the same for every iSCSI volume on '+str(ipaddress)+': volume '+str(name)+' has ' \
         +('no CHAP' if theirs is None else 'chapuser '+theirs)
 return None

def getlogin(token):
 global leaderip
 logindata = get('login',token)[0]
 if logindata == '_1':
  logmsg.sendlog('Lognno0','warning','system2',token)
  return {'response':'baduser'}
 oldtimestamp = logindata[1].split('/')[1]
 user = logindata[0].split('/')[1]
 if int(oldtimestamp) < int(timestamp()):
  dels('login',token)
  loggedusers.pop(token, None)
  logmsg.sendlog('Lognsa0','warning','system',user)
  print('isssss######ss##########33','baduser')
  return 'baduser'
 userdict, token = setlogin(leaderip, myhost,user,'!',token) 
 if token == 0:
  logmsg.sendlog('Lognsa0','warning','system',user)
  return 'baduser'
  print('#################33','baduser')
   
  return 'baduser'
 loggedusers[token] = userdict.copy()
 print('iamokkkkkkkkkkkkkkkkkk')
 return user 

@app.route('/api/v1/logout', methods=['GET','POST'])
def logout():
 global leaderip
 data = request.args.to_dict()
 token = str(data.get('token', ''))
 # QSD5.344: the UI Logout button now calls this (QC test 700).  No token: nothing to end, a clean answer (was a KeyError).
 if token in ('', '0'):
  return {'response': 'error', 'message': 'missing parameter: token'}
 if token.startswith('qsk.'):
  return {'response': 'error', 'message': 'not allowed for an API key'}
 # QSD5.344 (validator M3): this route has no login check, and etcddel matches a substring of key and value, so
 # 'token=a' or 'token=1' deleted every login record of the cluster.  A login token is 32 hex characters
 # (UnixChkUser.setlogin, token_hex(16)); only the record login/<user> whose value is <token>/<expiry> is deleted.
 if not LOGIN_TOKEN_RE.match(token):
  return {'response': 'error', 'message': 'invalid parameter: token'}
 # QSD5.344 (validator N1): read quietly. get() (etcdgetlocalpy) print()s the whole login list, so every active login
 # token went to the flask stdout on each logout; etcdgetpy (_getleader) is the same etcdctl read without the print,
 # and with the host 'etcd' it reads the local etcd (the endpoint etcdgetlocalpy uses).
 _del_login_record(_getleader('etcd', 'login', '--prefix'), token, 'etcd')
 try:
  _del_login_record(_getleader(leaderip, 'login', '--prefix'), token, leaderip)  # written on the leader (setlogin)
 except Exception:
  pass
 loggedusers.pop(token, None)
 return data

LOGIN_TOKEN_RE = re.compile(r'^[0-9a-f]{32}$')

def _del_login_record(records, token, etcdhost):
 # records: (key, value) pairs of the prefix 'login'; deletes the exact key whose value starts with '<token>/'
 for rec in records:
  if not isinstance(rec, tuple) or len(rec) != 2:
   continue
  key, val = str(rec[0]), str(rec[1])
  if key.startswith('login/') and val.startswith(token+'/'):
   try:
    subprocess.run(['etcdctl', '--endpoints=http://'+etcdhost+':2379', 'del', key], stdout=subprocess.PIPE, timeout=20)
   except Exception:
    pass

@app.route('/api/v1/login/test', methods=['GET','POST'])
def testlogin():
 data = request.args.to_dict()
 loginresponse = getlogin(data['token'])
 return { 'response': loginresponse }

@app.route('/api/v1/login', methods=['GET','POST'])
def login():
 data = request.args.to_dict()
 print('login request for', str(data.get('user'))[:32])     # QSD5.344: no password in the log
 userdict, token = setlogin(leaderip,myhost, data['user'],data['pass'])
 if token != 0:
  loggedusers[token] = userdict.copy()
  logmsg.sendlog('Lognsu0','info','system',data['user'])
  print('login ok', str(data.get('user'))[:32])
 else:
  print('login faileddddddddddddddddddd')
  logmsg.sendlog('Lognfa0','error','system',data['user'])
  token = 'baduser'
 return jsonify({'token':token})
@app.route('/api/v1/users/usersauth', methods=['GET','POST'])
@login_required
@audit_command
def usersauth(data):
 global allinfo
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 # QSD5.321 (test 625 step 5): only an existing user (a well formed usersinfo/<user> row) can get privileges; before, any
 # name was queued to Priv.py, which wrote usersinfo/<name> = '_1/<privs>' and broke users/userlist for everybody
 tochange = str(data.get('tochange', '') or '')
 auths = str(data.get('auths', '') or '')
 if not tochange or not auths or not usersinfo_ok(get('usersinfo/'+tochange)[0]):
  logmsg.sendlog('Priv1005','error',data['user'],tochange if tochange else '-')
  return {'response': 'error', 'message': 'invalid or missing parameter'}
 cmndstring = '/TopStor/Priv.py '+leader+' '+leaderip+' '+myhost+' '+myhostip+' '+tochange+' '+auths.replace(',','/')+' '+data['user']
 postchange(cmndstring)
 return data

# QSD5.336 (test 645 QX-046 step 5): a quota sent to volumes/config, as the zfs size VolumeChange<type> applies: a number with
# K/M/G/T (a bare number is GB, the unit of the volume record and of volumesinfo), 0 or none = no quota (as VolumeCreateNFS).
# None = not a valid quota.
QUOTA_RE = re.compile(r'^\s*(none|[0-9]+(?:\.[0-9]+)?)\s*(?:([KMGT])(?:I?B)?)?\s*$', re.IGNORECASE)
def _quotaarg(value):
 m = QUOTA_RE.match(str(value))
 if not m:
  return None
 if m.group(1).lower() == 'none':
  return None if m.group(2) else 'none'
 if float(m.group(1)) == 0:
  return 'none'
 return m.group(1)+(m.group(2) or 'G').upper()

@app.route('/api/v1/volumes/config', methods=['GET','POST'])
@login_required
@audit_command
def volumeconfig(data):
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 res = volumeconfig_do(data)
 if isinstance(res, dict):       # QSD5.352 r2: internal markers for users/userhomechange; the answer stays as it was
  res.pop('_refused', None)
  res.pop('_posted', None)
 return res

def volumeconfig_do(data):
 # the body of volumes/config; users/userhomechange (QSD5.352) uses it for the address of a home
 global allinfo, myhost
 getalltime()
 # QSD5.352 (QC 706): an unknown volume, or one whose registry record was lost (no ipaddress / Subnet / groups), ended in
 # a KeyError ('missing parameter: ipaddress') instead of the address checks below.
 if data.get('volume') not in allinfo['volumes']:
  logmsg.sendlog('VolCfa01','error',data['user'],logname(data.get('volume')))
  return {'response': data['response'], 'volume': data.get('volume'), 'error': 'novolume'}
 volume = allinfo['volumes'][data['volume']]
 for field in ('ipaddress', 'Subnet', 'groups'):
  volume.setdefault(field, '')
 # an empty word would shift every later argument of VolumeChange<type>: the home's own user / no group, subnet 24
 if not str(volume['groups']).strip():
  volume['groups'] = str(volume.get('name','')).rsplit('_',1)[0] if volume.get('prot') in ('HOME','HOMEE') else 'NoGroup'
 if not str(volume['Subnet']).strip():
  volume['Subnet'] = '24'
 # QSD5.352 r8 (validator r7, statusmount): a home is 'active' or 'disabled' (the canonical off value; 'disable' is taken
 # as it, any case).  Any other word was passed on: 'inactive' contains 'active', so VolumeChangeHOME took the home down
 # and VolumeCheck / cifs.py served it again in every cycle; a '/' broke the registry record.  Refused: invalidstatus.
 if volume.get('prot') in ('HOME', 'HOMEE') and 'statusmount' in data:
  sm = str(data['statusmount']).strip().lower()
  sm = 'disabled' if sm == 'disable' else sm
  if sm not in ('active', 'disabled'):
   return {'response': data['response'], 'volume': data.get('volume'), 'error': 'invalidstatus'}
  data['statusmount'] = sm
 # iSCSI CHAP (test 653 QX-054 step 5/6): checked first (HTTP 400, nothing changed); the secret is in no answer
 chapuser, chaptoken = None, None
 if 'ISCSI' in str(data.get('type', '')):
  chapuser, chaptoken = chap_config(data, volume)
  chap_hide(data)
  if chapuser is None:
   return chap_refuse(chaptoken)
 chap_hide(data)
 # QSD5.336: $4 of VolumeChange<type> is the quota. Not sent: the stored GB number (e.g. 1.0, no unit) as before, which the
 # scripts leave alone. Sent: checked here (HTTP 400 if bad) and passed with its unit or as none, which the scripts apply.
 quotaarg = str(volume['quota'])
 if 'quota' in data and 'ISCSI' not in str(data.get('type', '')):
  quotaarg = _quotaarg(data['quota'])
  if quotaarg is None:
   return jsonify({'response': 'error', 'error': 'badquota', 'volume': data['volume'], 'quota': str(data['quota']),
                   'message': 'invalid quota '+str(data['quota'])+': use a size such as 2G, 500M or 1.5T (K/M/G/T; a bare'
                              +' number is GB) or 0/none for no quota; volume not changed'}), 400
  data['quota'] = quotaarg
 data['owner'] = volume['host']
 if 'ipaddress' not in data:
   if len(str(volume['ipaddress'])) < 7:
    logmsg.sendlog('VolCfa01','error',data['user'],logname(data.get('volume')))
    return {'response': data['response'], 'volume': data.get('volume'), 'error': 'noaddress'}
   data['ipaddress'] = volume['ipaddress']
 else:
    datatype = ip_context(volume['prot'])

    if data['ipaddress'] != volume['ipaddress']:
        isvu =  int(is_valid_ip(data['ipaddress']))+int(is_unique_ip(data['ipaddress'],datatype))
        if isvu == 0:
            print('ip is valid')
        else:
            if isvu < 100:
                logmsg.sendlog('IPaddrfa','error','system',loggedusers[data['token']]['user'])
                data['_refused'] = 'invalidip'
            elif isvu > 10 and isvu < 120: 
                logmsg.sendlog('IPadduqfa','error','system',loggedusers[data['token']]['user'])
                data['_refused'] = 'ipinuse'
            else:
                logmsg.sendlog('IPnamuqfa','error','system',loggedusers[data['token']]['user'])
                data['_refused'] = 'nameinuse'
            return data
 if data['owner'] == leader:
  ownerip = leaderip
 else:
  ownerip = allinfo['hosts'][data['owner']]['ipaddress']
 datastr = ''
 data['owner'] = allinfo['hosts'][allinfo['pools'][volume['pool']]['host']]['name']
 if 'ISCSI' in data['type']:
  # the requested CHAP, or the volume's own when none is sent (it was replaced here by one built-in pair, test 653 step 5)
  data['chapuser'] = chapuser
  if 'initiators' not in data:
   data['initiators'] = volume['initiators']
  if 'portalport' not in data:
   data['portalport'] = volume['portalport']
  for ele in data:
   if ele not in CHAP_SECRETS:
    volume[ele] = data[ele]
  volume['chappas'] = chaptoken
  datastr = volume['pool']+' '+volume['name']+' '+str(volume['quota'])+' '+data['ipaddress']+' '+str(volume['Subnet'])+' '+data['portalport']+' '+data['initiators']+' '+chapuser+' '+chaptoken+' '+volume['statusmount']+' '+data['user']+' '+data['owner']+' '+data['user']
 else:

  if 'groups' in data and len(data['groups']) < 1: 
   data['groups'] = 'NoGroup'
  if 'groups' in data:
   grps = share_groups(data['groups'])
   if grps is None:
    data['error'] = 'invalidgroup'
    return data
   data['groups'] = only_everyone(grps)
  for ele in data:
   if ele != 'quota':   # the record's quota stays the GB number from zfs (putzpool), not the request's '2G'
    volume[ele] = data[ele]
  datastr = volume['pool']+' '+volume['name']+' '+quotaarg+' '+volume['groups']+' '+volume['ipaddress']+' '+str(volume['Subnet'])+' '+volume['statusmount']+' '+volume['host']+' '+volume['user']
  print('33333333333333333333333333333333333333333333333#############################')
  print('volume',logsafe(volume))
  print('owner',ownerip)
  print('33333333333333333333333333333333333333333333333#############################')
 cmndstring = '/TopStor/VolumeChange'+data['type']+' '+leaderip+' '+datastr
 postchange(cmndstring,data['owner'])
 data['_posted'] = True          # QSD5.352 r2: users/userhomechange goes on to the quota only after this
# z= cmndstring.split(' ')
# msg={'req': 'Pumpthis', 'reply':z}
# sendhost(ownerip, str(msg),'recvreply',myhost)
 #config(data)
 return data

@app.route('/api/v1/users/userhomechange', methods=['GET','POST'])
@login_required
@audit_command
def userhomechange(data):
 # QSD5.352 (QC 706, QX-056 / QX-107): the Users page edits the quota and the address of a user's home folder
 # (topstorweb api/users.js changeUserHome: name, tenant, Volsize '<GB>', HomeAddress, HomeSubnet); the route did not
 # exist (404).  Everything is checked first, then the address goes the volumes/config way (VolumeChangeHOME) and the
 # quota to VolumeQuotaHOME on the node that owns the pool.  Privilege: HOME (the same as the home scripts).
 global allinfo
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 name = str(data.get('name') or '')
 reply = {'response': data['response'], 'name': name}
 if not has_privilege('HOME', data['user']):
  logmsg.sendlog('Priv1004','error','system',data['user'])
  reply['error'] = 'noprivilege'
  return reply
 getalltime()
 homes = [ v for k, v in allinfo.get('volumes', {}).items()
           if v.get('prot') in ('HOME', 'HOMEE') and str(k).rsplit('_', 1)[0] == name ]
 if not homes:
  logmsg.sendlog('HomCfa01','error',data['user'],logname(name))
  reply['error'] = 'nohome'
  return reply
 home = homes[0]
 reply['volume'] = home['name']
 size = data.get('Volsize')
 gb = ''
 if size not in (None, ''):
  m = re.fullmatch(r'([0-9]+(\.[0-9]+)?)[Gg]?', str(size))
  if not m or float(m.group(1)) <= 0 or float(m.group(1)) > 1000000:
   logmsg.sendlog('HomQfa01','error',data['user'],logname(name),logname(str(size)))
   reply['error'] = 'invalidsize'
   return reply
  gb = m.group(1)
 addr = data.get('HomeAddress')
 subnet = str(data.get('HomeSubnet') or home.get('Subnet') or '24')
 newaddr = addr not in (None, '') and (str(addr) != str(home.get('ipaddress')) or subnet != str(home.get('Subnet')))
 if newaddr:
  if subnet not in ('8', '16', '24', '32') and not re.fullmatch(r'([1-9]|[12][0-9]|3[0-2])', subnet):
   logmsg.sendlog('IPaddrfa','error','system',data['user'])
   reply['error'] = 'invalidsubnet'
   return reply
  if str(addr) != str(home.get('ipaddress')):
   isvu = int(is_valid_ip(addr))+int(is_unique_ip(addr, ip_context('HOME')))
   if isvu != 0:
    if isvu < 100:
     logmsg.sendlog('IPaddrfa','error','system',data['user'])
     reply['error'] = 'invalidip'
    elif isvu > 10 and isvu < 120:
     logmsg.sendlog('IPadduqfa','error','system',data['user'])
     reply['error'] = 'ipinuse'
    else:
     logmsg.sendlog('IPnamuqfa','error','system',data['user'])
     reply['error'] = 'nameinuse'
    return reply
 if not newaddr and not gb:
  reply['error'] = 'nothingtochange'
  return reply
 owner = allinfo['hosts'][allinfo['pools'][home['pool']]['host']]['name']
 if newaddr:
  cfg = {'response': data['response'], 'user': data['user'], 'token': data.get('token'), 'volume': home['name'],
         'type': 'HOME', 'ipaddress': str(addr), 'Subnet': subnet}
  # QSD5.352 r2 (validator R3a): the result was ignored; a refused address change (novolume, noaddress, invalidgroup,
  # an IP check, a CHAP answer) still answered HomeAddress and went on to the quota.  Only a change that was really
  # posted counts; otherwise the refusal is the answer and the quota is NOT changed.
  res = volumeconfig_do(cfg)
  if not isinstance(res, dict) or not res.get('_posted'):
   res = res if isinstance(res, dict) else {}
   reply['error'] = res.get('error') or res.get('_refused') or res.get('message') or 'addressnotchanged'
   return reply
  reply['HomeAddress'] = str(addr)
  reply['HomeSubnet'] = subnet
 if gb:
  postchange('/TopStor/VolumeQuotaHOME '+leaderip+' '+home['pool']+' '+home['name']+' '+gb+'G '+data['user'], owner)
  reply['Volsize'] = gb
 return reply

@app.route('/api/v1/user/changepass', methods=['GET','POST'])
@login_required
@audit_command
def changepass(data):
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 data['user'] = data['response']
 # a user changes only his own password; another user's password needs the privilege Box_Users (admin/system always).
 # Without this gate any logged-in user rewrote usershash/<other user> (test 613 step 6), while UnixChangePass skipped the OS part.
 if str(data.get('username', '')) != str(data['response']) and not has_privilege('Box_Users', data['response']):
  logmsg.sendlog('Priv1004','error','system',data['response'])
  data['error'] = 'noprivilege'
  return data
 # QSD5.344: this call changes a password and nothing else.  Hostconfig.config() also changes the alias, the cluster
 # address, the time zone, NTP, DNS, ports ... (the Node Config calls of hosts/config, privilege 'Error'); passing the
 # whole request let any logged-in user change those through user/changepass without the privilege.  Only the three
 # password fields go on; the own-user / admin check (QSD5.337) and the reserved names (QSD5.338) stay in config().
 # The answer no longer echoes the request (it carried the new password and the token).
 req = {'user': data['user'], 'username': data.get('username')}
 if 'password' in data:      # only when given: a None password made config() log Unlinfa12 for nothing
  req['password'] = data['password']
 target = str(req['username'] or '')
 # QSD5.344: admin setting a password for a user that does not exist used to write usershash/<name>; a later Add User
 # of that name was then refused as 'already used' (QC test 671).  admin always exists.
 if 'password' in req and req['user'] in ('admin', 'system') and target not in ('', 'admin') \
    and not check_password_target(target) and str(get('usersinfo/'+target)[0]) in ('_1', '-1', '', 'None'):
  logmsg.sendlog('Unlinfa13','error',req['user'],logname(target))
  return {'response': data['response'], 'username': target, 'error': 'nouser'}
 config(leader, leaderip,myhost, req)
 reply = {'response': data['response'], 'username': req['username']}
 if 'error' in req:
  reply['error'] = req['error']
 return reply



def alias_in_use(alias, me):
 # True when alias equals (case-insensitive) the host name or the alias of a node other than 'me'.
 # Names come from the local etcd: ready/<host>, ActivePartners/<host> and alias/<host> (so a node that is down
 # but keeps an alias still counts).
 new = alias.strip().lower()
 me = me.strip().lower()
 if new == '':
  return False
 def isplaceholder(v):
  v = str(v).strip()
  return v in ('', '-1') or re.fullmatch(r'_\d+', v) is not None
 for prefix in ('ready/', 'ActivePartners/'):
  for kv in get(prefix, '--prefix'):
   if not isinstance(kv, tuple) or not str(kv[0]).startswith(prefix):
    continue
   host = str(kv[0])[len(prefix):].strip().lower()
   if host != '' and host != me and host == new:
    return True
 for kv in get('alias/', '--prefix'):
  if not isinstance(kv, tuple) or not str(kv[0]).startswith('alias/'):
   continue
  host = str(kv[0])[len('alias/'):].strip().lower()
  if host == me or isplaceholder(kv[1]):
   continue
  if str(kv[1]).strip().lower() == new:
   return True
 return False

@app.route('/api/v1/hosts/config', methods=['GET','POST'])
@login_required
@audit_command
def hostconfig(data):
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 # Node Config is the privilege 'Error' (usersauth); it used to be only a hint for the UI
 if not has_privilege('Error', data['response']):
  logmsg.sendlog('Priv1004','error','system',data['response'])
  data['error'] = 'noprivilege'
  return data
 # alias: letters, digits, '.' and '-' only (the node start scripts use it unquoted in shell commands; '_' is the
 # sync-key separator); an empty alias is left to the old behaviour.  Refused before anything is stored.
 if data.get('alias','') != '' and not re.fullmatch(r'[A-Za-z0-9.-]{1,64}', str(data['alias'])):
  return jsonify({'response':'error','message':'invalid character in parameter: alias'}), 400
 # alias: not the host name or alias of ANOTHER node (case-insensitive; '', '-1' and the '_N' placeholders mean
 # "no alias").  The node's own name / current alias and an empty alias stay allowed.  Refused before anything is stored.
 if data.get('alias','') != '' and alias_in_use(str(data['alias']), str(data.get('name',''))):
  return jsonify({'response':'error','message':'alias already in use: '+str(data['alias'])}), 400
 # ntp (test 672 step 3): an IPv4 address or an RFC 1123 host name ('ntp..bad' was written to etcd and chrony.conf);
 # '' and '_1' (not set) stay allowed.  Refused before anything is stored.
 for key in ('ntp', 'ntpName'):
  val = str(data.get(key, '')).strip()
  if val in ('', '_1'):
   continue
  okv = all(re.fullmatch(r'(25[0-5]|2[0-4]\d|1?\d?\d)(\.(25[0-5]|2[0-4]\d|1?\d?\d)){3}', e) or
            (len(e) <= 253 and not re.fullmatch(r'[0-9.]+', e) and
             all(re.fullmatch(r'[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?', l) for l in e.rstrip('.').split('.')))
            for e in re.split(r'[\s,]+', val) if e)
  if not okv:
   return jsonify({'response':'error','message':'invalid address or host name in parameter: '+key}), 400
 if 'ipaddr' in data:
    isvu =  int(is_valid_ip(data['ipaddr']))+int(is_unique_ip(data['ipaddr']))
    if isvu == 0:
        print('ip is valid')
    else:
        if isvu < 100:
            logmsg.sendlog('IPaddrfa','error','system',loggedusers[data['token']]['user'])
        elif isvu > 10 and isvu < 120: 
            logmsg.sendlog('IPadduqfa','error','system',loggedusers[data['token']]['user'])
        else:
            logmsg.sendlog('IPnamuqfa','error','system',loggedusers[data['token']]['user'])
        return data
 if 'cluster' in data:
    dataip = data['cluster'].split('/')[0]   
    isvu =  int(is_valid_ip(dataip))+int(is_unique_ip(dataip))
    if 'ipaddr' in data:
        if dataip == data['ipaddr']:
            isvu = 1
    if isvu == 0:
        print('ip is valid')
    else:
        if isvu == 1:
            logmsg.sendlog('IPaddrclufa','error','system',loggedusers[data['token']]['user'])
        elif isvu < 100:
            logmsg.sendlog('IPaddrfa','error','system',loggedusers[data['token']]['user'])
        elif isvu > 10 and isvu < 120: 
            logmsg.sendlog('IPadduqfa','error','system',loggedusers[data['token']]['user'])
        else:
            logmsg.sendlog('IPnamuqfa','error','system',loggedusers[data['token']]['user'])
        return data

 datastr = ''
 for ele in data:
  datastr += ele+'='+data[ele]+' '
 datastr = datastr[:-1]
 print('#############################')
 print(logsafe(data))
 print('###########################')

 if 'discovered' in data:
  dleaderip = leaderip
  dleader   = get(dleaderip, 'leader')[0]
  config(dleader, dleaderip, myhost, data)
  return data

 config(leader, leaderip, myhost, data)
 return data

@app.route('/api/v1/hosts/joincluster', methods=['GET','POST'])
@login_required
@audit_command
def hostjoincluster(data):
 global leaderip, myhost
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 data['user'] = data['response']
 if not has_privilege('Error', data['user']):
  logmsg.sendlog('Priv1004','error','system',data['user'])
  data['joinstatus'] = 'noprivilege'
  return data
 # optional changes made together with the join: they travel to the node in tojoin/<name>
 if data.get('ipaddr'):
  isvu = int(is_valid_ip(data['ipaddr']))+int(is_unique_ip(data['ipaddr']))
  if isvu != 0:
   if isvu < 100:
    logmsg.sendlog('IPaddrfa','error','system',data['user'])
   else:
    logmsg.sendlog('IPadduqfa','error','system',data['user'])
   data['joinstatus'] = 'invalid ip'
   return data
  if data.get('ipaddrsubnet') and not (str(data['ipaddrsubnet']).isdigit() and 1 <= int(data['ipaddrsubnet']) <= 32):
   data['joinstatus'] = 'invalid subnet'
   return data
 if data.get('alias') and ('|' in data['alias'] or '=' in data['alias']):
  data['joinstatus'] = 'invalid alias'
  return data
 discover()
 data['leaderip'] = leaderip
 data ['myhost'] = myhost
 Joincluster.do(data) 
 cmndstring = '/TopStor/promserver.sh '+leaderip+' from fapi'
 postchange(cmndstring)
 return data


@app.route('/api/v1/hosts/evacuate', methods=['GET','POST'])
@login_required
@audit_command
def hostevacuate(data):
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 data['user'] = data['response']
 #with open('/root/Evacuate','w') as f:
  #f.write(" ".join([leaderip, myhost, data['name'], data['user']]))
 discover()
 Evacuate.do(leaderip, myhost, data['name'], data['user']) 
 return data

@app.route('/api/v1/volumes/snapshots/snaprollback', methods=['GET','POST'])
@login_required
@audit_command
def volumesnapshotrol(data):
 global allinfo, myhost
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 getalltime()
 volume = allinfo['snapshots'][data['name']]['volume']
 pool = allinfo['snapshots'][data['name']]['pool']
 data['owner'] = allinfo['snapshots'][data['name']]['host']
 ownerip = allinfo['hosts'][data['owner']]['ipaddress']
 cmndstring = "/TopStor/SnapShotRollback "+pool+" "+volume+" "+data['name']+" "+data['user']
 postchange(cmndstring,data['owner'])
# z= cmndstring.split(' ')
# msg={'req': 'Pumpthis', 'reply':z}
 print('##################################')
 print(logsafe(data))
 print('################################333')
# sendhost(ownerip, str(msg),'recvreply',myhost)
        		 
 return data


@app.route('/api/v1/volumes/snapshots/perioddelete', methods=['GET','POST'])
@login_required
@audit_command
def volumesnapshotperioddel(data):
 global allinfo, myhost
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 getalltime()
 # QSD5.346 (test 661 QX-062 step 5): an unknown period (not in the leader's Snapperiod records) raised KeyError (HTTP 500)
 if data.get('name','') not in allinfo['snapperiods']:
  return jsonify({'response': 'error', 'error': 'noperiod', 'message': 'No such snapshot period: '+str(data.get('name',''))}), 400
 data['owner'] = allinfo['snapperiods'][data['name']]['host']
 ownerip = allinfo['hosts'][data['owner']]['ipaddress']
 cmndstring = "/TopStor/SnapShotPeriodDelete "+leaderip+" "+data['name']+" "+data['user']
 postchange(cmndstring,data['owner'])
# z= cmndstring.split(' ')
# msg={'req': 'Pumpthis', 'reply':z}
# sendhost(ownerip, str(msg),'recvreply',myhost)
 return data  


@app.route('/api/v1/volumes/snapshots/snapshotdel', methods=['GET','POST'])
@login_required
@audit_command
def volumesnapshotdel(data):
 global allinfo, myhost 
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 getalltime()
 volume = allinfo['snapshots'][data['name']]['volume']
 pool = allinfo['snapshots'][data['name']]['pool']
 data['owner'] = allinfo['snapshots'][data['name']]['host']
 ownerip = allinfo['hosts'][data['owner']]['ipaddress']
 cmndstring = "/TopStor/SnapShotDelete "+pool+" "+volume+" "+data['name']+" "+data['user']
 postchange(cmndstring,data['owner'])
# z= cmndstring.split(' ')
# msg={'req': 'Pumpthis', 'reply':z}
 print('##################################')
 print(logsafe(data))
 print('################################333')
# sendhost(ownerip, str(msg),'recvreply',myhost)
        		 
 return data

@app.route('/api/v1/volumes/volumeactive', methods=['GET','POST'])
@login_required
@audit_command
def volumeactive(data):
 global allinfo, myhost
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 pool = allinfo['volumes'][data['name']]['pool']
 prot = allinfo['volumes'][data['name']]['prot']
 data['owner'] = allinfo['volumes'][data['name']]['host']
 ownerip = allinfo['hosts'][data['owner']]['ipaddress']
 cmndstring = "/TopStor/Volumeactive.py "+leaderip+" "+myhost+" "+pool+" "+data['name']+" "+prot+" "+data['active']+" "+data['user']
 postchange(cmndstring,data['owner'])
 print('##################################')
 print('volumeactive',cmndstring)
 print('##################################')
# z= cmndstring.split(' ')
# msg={'req': 'Pumpthis', 'reply':z}
# sendhost(ownerip, str(msg),'recvreply',myhost)
 return data



# A volume that has an etcd key volumes/<TYPE>/<host>/<pool>/<name> but no dataset (allinfo drops it), e.g. the leftover of a
# failed create (test 635: size=0G refused by zfs, the key kept the address, volumedel was a KeyError = HTTP 500).  An NFS key
# goes to VolumeDeleteNFS on the host of the key (it removes the keys, a container/address if any, and skips the zfs destroy);
# other types go to their VolumeDelete<TYPE> as before; an NFS key whose host is not ready is removed here.  No key at all: a
# clean answer (error novolume, NFS1001) instead of HTTP 500.
def volumedel_leftover(data):
 name = str(data.get('name', ''))
 user = data.get('user', 'system')
 keys = [k for k in get('volumes', '--prefix') if len(str(k[0]).split('/')) >= 5 and str(k[0]).split('/')[-1] == name] if name else []
 if not keys:
  logmsg.sendlog('NFS1001', 'error', user, name)
  data['error'] = 'novolume'
  return data
 for key in keys:
  _, vtype, host, pool = str(key[0]).split('/')[:4]
  data['owner'] = host
  # the script on the key's host decides (a dataset that exists after all, allinfo not refreshed yet, is deleted as usual)
  if postchange('/TopStor/VolumeDelete'+vtype+' '+leaderip+' '+pool+' '+name+' '+vtype+' '+user, host) != 'host is not ready' or vtype != 'NFS':
   continue
  logmsg.sendlog('NFS1000', 'info', user, pool+'/'+name)
  dels(key[0])
  for pfx in ('vol', 'replivol', 'size', 'tenant'):
   dels(pfx, name)
  stamp = 'volumes_'+str(int(timestamp()))
  put(leaderip, 'sync/volumes/'+pool+'_'+name+'/request', stamp)
  put(leaderip, 'sync/volumes/'+pool+'_'+name+'/request/'+myhost, stamp)
  logmsg.sendlog('NFS1002', 'info', user, pool+'/'+name)
 return data

@app.route('/api/v1/volumes/volumedel', methods=['GET','POST'])
@login_required
@audit_command
def volumedel(data):
 global allinfo, myhost
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 getalltime()
 if data.get('name') not in allinfo['volumes']:
  return volumedel_leftover(data)
 pool = allinfo['volumes'][data['name']]['pool']
 data['owner'] = allinfo['volumes'][data['name']]['host']
 ownerip = allinfo['hosts'][data['owner']]['ipaddress']
 cmndstring = "/TopStor/VolumeDelete"+data['type']+" "+leaderip+" "+pool+" "+data['name']+" "+data['type']+" "+data['user']
 postchange(cmndstring,data['owner'])
# z= cmndstring.split(' ')
# msg={'req': 'Pumpthis', 'reply':z}
 print('##################################')
 print(logsafe(data))
 print('################################333')
# sendhost(ownerip, str(msg),'recvreply',myhost)
        		 
 return data

# The groups of a share without <group> (exact names; 'NoGroup' when none is left, as volumes/config sends it).
def groups_without(groups, group):
 rest = [g for g in str(groups).split(',') if g and g not in ('NoGroup', 'nogroup', group)]
 return only_everyone(','.join(rest)) if rest else 'NoGroup'

# A group delete (test 627 step 3): UnixDelGroup removed only the unix group and usersigroup/<group>; the shares that listed
# the group kept it in etcd, in their smb conf (write list = <group>) and in the dataset ACL (group:<gid>:rwx, a numeric orphan
# once the gid is free), so a group created later with that name or gid got the old rights.  Before UnixDelGroup is queued,
# every CIFS / NFS / HOME share that lists the group is changed on the node that owns its pool with the command volumes/config
# sends (VolumeChange<type>), the group taken out: the scripts rewrite etcd, the smb conf / exports and the ACL (setfacl -b,
# then the remaining groups by name).  Domain shares (groups 'DOMAIN') and iSCSI have no group list and are left alone.
def volumes_drop_group(group, userreq):
 try:
  getalltime('yes')
  vols = list(allinfo['volumes'].values())
 except Exception as e:
  print('volumes_drop_group: no volumes info', e)
  return
 for volume in vols:
  prot = str(volume.get('prot', ''))
  if prot in ('CIFS', 'NFS'):
   vtype = prot
  elif 'HOME' in prot:
   vtype = 'HOME'
  else:
   continue
  if group not in str(volume.get('groups', '')).split(','):
   continue
  try:
   owner = allinfo['hosts'][allinfo['pools'][volume['pool']]['host']]['name']
   user = userreq if has_privilege(vtype, userreq) else 'system'
   datastr = volume['pool']+' '+volume['name']+' '+str(volume['quota'])+' '+groups_without(volume['groups'], group)+' '+\
             volume['ipaddress']+' '+str(volume['Subnet'])+' '+volume['statusmount']+' '+volume['host']+' '+user
  except Exception as e:
   print('volumes_drop_group: skipped', volume.get('name'), e)
   continue
  postchange('/TopStor/VolumeChange'+vtype+' '+leaderip+' '+datastr, owner)

@app.route('/api/v1/groups/groupdel', methods=['GET','POST'])
@login_required
@audit_command
def groupdel(data):
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 if data.get('name') == EVERYONE:
  data['error'] = 'everyonefixed'
  return data
 if has_privilege('Box_Users', data['user']):
  volumes_drop_group(str(data.get('name')), data['user'])
 cmndstring = '/TopStor/UnixDelGroup '+leaderip+' '+data.get('name')+' '+data['user']
 postchange(cmndstring)
 unshare_group(data.get('name'), data)
 return data

def unshare_group(name, data):
 # QSD5.352 fix16 (QC 627, QX-028 step 4): UnixDelGroup removed the group's ACL entries and the group, but every CIFS / NFS
 # share kept the deleted name in its registry record (groups field) and in its share file (write list = <group>).  A new
 # group of the same name then matched that share by name (silent inheritance), and is_unique_name refused the name meanwhile
 # (IPnamuqfa).  Each share that names the group is changed the volumes/config way (VolumeChange<type> on the owner node
 # rebuilds record and share file) with the group left out; no group left = NoGroup.
 global allinfo
 try:
  getalltime()
  vols = list(allinfo.get('volumes', {}).items())
 except Exception as e:
  print('unshare_group: volumes', e)
  return
 for vname, vol in vols:
  if vol.get('prot') not in ('CIFS', 'NFS'):
   continue
  grps = [ g.strip() for g in str(vol.get('groups', '')).split(',') if g.strip() ]
  if name not in grps:
   continue
  rest = [ g for g in grps if g != name ]
  req = {'response': data['response'], 'user': data['user'], 'token': data.get('token'), 'type': vol['prot'],
         'volume': vname, 'groups': ','.join(rest) if rest else 'NoGroup'}
  try:
   res = volumeconfig_do(req)
   print('unshare_group:', vname, 'groups', req['groups'], 'error' in res if isinstance(res, dict) else res)
  except Exception as e:
   print('unshare_group:', vname, e)

@app.route('/api/v1/partners/partnerdel', methods=['GET','POST'])
@login_required
@audit_command
def partnerdel(data):
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 cmndstring = '/TopStor/PartnerDel.py '+data.get('name')+' no '+data['user']
 postchange(cmndstring)
 return data



@app.route('/api/v1/users/userdel', methods=['GET','POST'])
@login_required
@audit_command
def userdel(data):
 global allinfo
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 # QSD5.352 r5 (validator N4): no privilege check here: UnixDelUser checks Box_Users only later, but the login tokens of <name>
 # were dropped (logged out) before, by any logged-in user; the NFS tenant path (TenantDelUser) had no check at all.
 if not has_privilege('Box_Users', data.get('user')):
  logmsg.sendlog('Priv1004','error','system',str(data.get('user')))
  return {'response': data.get('response'), 'error': 'noprivilege'}
 if data['tenant'] == 'Cluster':
    cmndstring = '/TopStor/UnixDelUser '+leaderip+' '+data.get('name')+' '+data['user']
    postchange(cmndstring)
    # QSD5.337: the deleted user's login token stayed valid (loggedusers + etcd login/<user>): drop both
    if data.get('name') not in ('admin', 'Everyone', 'NoUser', 'system'):
     for tok in [t for t, v in list(loggedusers.items()) if v.get('user') == data.get('name')]:
      loggedusers.pop(tok, None)
     try:
      subprocess.run(['etcdctl', '--endpoints=http://etcd:2379', 'del', 'login/'+data.get('name')], stdout=subprocess.PIPE, timeout=20)
     except Exception:
      pass
    # the home folder of the user goes with the user (its dataset is <user>_<id>, protocol HOME)
    if data.get('name') not in ('admin', 'Everyone', 'NoUser'):
     getalltime()
     for volname, vol in list(allinfo['volumes'].items()):
      if vol.get('prot') in ('HOME', 'HOMEE') and volname.rsplit('_',1)[0] == data.get('name'):
       postchange('/TopStor/VolumeDeleteHOME '+leaderip+' '+vol['pool']+' '+volname+' HOME '+data['user'], vol['host'])
 else:
    return TenantDelUser(data)
 return data

@app.route('/api/v1/groups/UnixAddgroup', methods=['GET','POST'])
@login_required
@audit_command
def UnixAddGroup(data):
 global allusers, allgroups
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 if data.get('name') == EVERYONE:
  data['error'] = 'everyonefixed'
  return data
 usrstr = ''
 usrs = data['users']
 if len(usrs) < 1:
  usrstr = 'NoUser'
 else:
  _ulist = _users_for_ids()
  for usr in usrs.split(','):
   for suser in _ulist:
    if str(suser['id']) == str(usr):
     usrstr += suser['name']+',' 
  usrstr = usrstr[:-1]

 if check_group_name(data.get('name')):     # QSD5.338: system account / group names (UnixAddGroup would groupdel them)
    logmsg.sendlog('Unlin1027rs','error',data['user'],logname(data.get('name')))
    data['error'] = 'reservedname'
    return data
 # QSD5.352 (QC 708): length and characters of a new group name, answered here and not by a failing script (Unlin1120).
 # The name after login_required stripped the blanks (a group 'q104 g' stays 'q104g', QX-104).
 why = check_new_group_name(data.get('name'))
 if why:
    logmsg.sendlog(CODE_GROUPNAME,'error',data['user'],logname(data.get('name')))
    data['error'] = 'invalidname'
    data['message'] = why
    return data
 if int(is_unique_name(data['name']))==1000:
    logmsg.sendlog('IPnamuqfa','error','system',loggedusers[data['token']]['user'])
    data['error'] = 'nameinuse'     # QSD5.352 fix16 (QC 627): the refusal was only in the log, the reply looked accepted
    return data
 cmndstring = '/TopStor/UnixAddGroup '+leaderip+' '+data['name']+' '+' users'+usrstr+' '+data['user']
 postchange(cmndstring)
 return data

PARTNER_PORT_MIN = 3001
PARTNER_PORT_MAX = 8000

def partner_ports_used():
 # ports already given to a partner entry:  Partner/<alias>_<type> = <ip>/<type>/<port>/<phrase>
 used = set()
 try:
  for partner in etcdgetjson(leaderip,'Partner/','--prefix'):
   split = partner["prop"].split('/')
   if len(split) > 2:
    used.add(str(split[2]).strip())
 except Exception as e:
  print('partner_ports_used:', e)
 return used

def port_listening(port):
 # a listener of this node holds the port (ss), or it cannot be bound (bind test)
 try:
  out = subprocess.run(['ss','-ltnH'],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,timeout=10).stdout.decode('utf-8','replace')
  for line in out.split('\n'):
   cols = line.split()
   if len(cols) > 3 and cols[3].rsplit(':',1)[-1] == str(port):
    return True
 except Exception as e:
  print('port_listening ss:', e)
 sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
 try:
  sock.bind(('0.0.0.0', int(port)))
  return False
 except OSError:
  return True
 finally:
  sock.close()

def partner_port_free(port, used=None):
 try:
  port = int(str(port).strip())
 except (TypeError, ValueError):
  return False
 if port < PARTNER_PORT_MIN or port > PARTNER_PORT_MAX:
  return False
 if used is None:
  used = partner_ports_used()
 return str(port) not in used and not port_listening(port)

@app.route('/api/v1/partners/freeport', methods=['GET'])
@login_required
@audit_command
def api_partners_freeport(data):
 # a random free port in 3001..8000 for a new partner; no side effects
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 import random
 used = partner_ports_used()
 for _ in range(50):
  port = random.randint(PARTNER_PORT_MIN, PARTNER_PORT_MAX)
  if partner_port_free(port, used):
   return {'port': port}
 return {'port': 0, 'response': 'select another port'}

def partner_alias_key(alias):
 # the alias as PartnerAdd.py stores it (Partner/<alias>_<type>): '_' dropped, '/' written as ':::'
 return str(alias or '').replace('_','').replace('/',':::')

def partner_alias_taken(alias, ptype):
 # QSD5.345: a partner of this alias and type exists already (Partner/<alias>_<type>, compared without case).  The add used
 # to overwrite it silently with the new address, port and phrase (QC tests 694, 705); the other type of the same alias
 # stays allowed (a cluster can be both the sender and the receiver of another one).
 want = (partner_alias_key(alias)+'_'+str(ptype or '')).lower()
 try:
  for partner in etcdgetjson(leaderip,'Partner/','--prefix'):
   if str(partner['name']).split('/',1)[-1].lower() == want:
    return True
 except Exception as e:
  print('partner_alias_taken:', e)
 return False

def partner_other_type(alias, ptype):
 # QSD5.345: the stored name of the same alias under the other type ('<alias>_Sender' for a Receiver add and back), lower
 # case; its address may be the address of the new entry (is_unique_ip partnerskip).  Empty for an unknown type.
 other = {'sender': 'Receiver', 'receiver': 'Sender'}.get(str(ptype or '').lower())
 if not other:
  return ()
 return ((partner_alias_key(alias)+'_'+other).lower(),)

@app.route('/api/v1/partners/AddPartner', methods=['GET','POST'])
@login_required
@audit_command
def AddPartner(data):
 if 'baduser' in data['response']:
  return {'response': 'baduser'} 
 # test 674 step 7: the pass reached PartnerAdd.py with a trailing newline (the command line is split on blanks) and became
 # part of an etcd sync key; every key list read after it paired keys with the wrong values and checksyncs wrote marks
 # without end.  alias / type / pass go into the command line, the 'Partner/<alias>_<type>' key and the
 # '<ip>/<type>/<port>/<pass>' value: no blank, control character, '/', '_' or ':' in them.
 for key, pat in (('alias', r'[A-Za-z0-9.-]{1,64}'), ('type', r'[A-Za-z]{1,32}'), ('pass', r'[^\s/_:]{1,128}')):
  if not re.fullmatch(pat, str(data.get(key, ''))):
   return jsonify({'response':'error','message':'invalid character in parameter: '+key}), 400
 # QSD5.345: checked before the address: the same alias with the same address used to end in the address refusal with a
 # success-looking answer
 if partner_alias_taken(data.get('alias'), data.get('type')):
  logmsg.sendlog('Partner1001','error',data.get('user','system'),partner_alias_key(data.get('alias')))
  return 'partner alias already exists'
 # the address of the same alias under the other type may be shared (one cluster as Sender and Receiver); any other
 # partner, node, leader or volume address stays refused (IPadduqfa)
 isvu =  int(is_valid_ip(data['ip']))+int(is_unique_ip(data['ip'], partnerskip=partner_other_type(data.get('alias'), data.get('type'))))
 if isvu == 0:
        print('ip is valid')
 else:
        if isvu < 100:
            logmsg.sendlog('IPaddrfa','error','system',loggedusers[data['token']]['user'])
        elif isvu > 10 and isvu < 120: 
            logmsg.sendlog('IPadduqfa','error','system',loggedusers[data['token']]['user'])
        else:
            logmsg.sendlog('IPnamuqfa','error','system',loggedusers[data['token']]['user'])
        return data

 # the port must be 3001-8000, not used by another partner and not listened on by this node: nothing is authorized otherwise
 if 'port' not in data or not partner_port_free(data['port']):
  logmsg.sendlog('Partnportfa','error','system',loggedusers[data['token']]['user'])
  return 'select another port'

 print('AddPartner', logsafe(data))
 cmdstring = '/TopStor/PartnerAdd.py '+data['ip']+' '+data['alias']+' '+data['type']+' '+data['port']+' '+data['pass']+' '+data['user'] + ' init'
 postchange(cmdstring)
 return data


@app.route('/api/v1/tenant/adduser', methods=['GET','POST'])
@login_required
@audit_command
def TenantAddUser(data):
 global allgroups, leaderip
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 # QSD5.352 r5 (validator N4): no privilege check (TenantAddUser has no privthis): any logged-in user could add an NFS tenant
 # user with any uid (0 too) and restart the NFS container.  Same privilege as users/UnixAddUser.
 if not has_privilege('Box_Users', data.get('user')):
  logmsg.sendlog('Priv1004','error','system',str(data.get('user')))
  return {'response': data.get('response'), 'error': 'noprivilege'}
 volinfo = get('vol',data['tenant'])[0]
 data['owner']= 'leader' 
 if 'NFS' not in str(volinfo[0]):     # r5: a tenant that is no NFS volume raised UnboundLocalError (cmndstring), HTTP 500
  return {'response': data.get('response'), 'error': 'notnfs'}
 if 'NFS' in volinfo[0]:
    data['owner'] = volinfo[0].split('/')[2]
    pool = volinfo[0].split('/')[3]
    grp = data['groups']
    if str(grp) != '0' and str(grp) != volinfo[1].split('_u_')[2].split(':')[0]:
        grp = 'NoGroup'
    cmndstring = '/TopStor/TenantAddUser '+leaderip+' '+data['response']+' '+pool+' '+data['tenant']+' '+data['name']+' '+data['userid']+' '+grp
 postchange(cmndstring,data['owner'])
 return data
 
def TenantDelUser(data):
 global allgroups, leaderip
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 # QSD5.352 r5 (validator N4): reached only through users/userdel (checked there); kept here too
 if not has_privilege('Box_Users', data.get('user')):
  logmsg.sendlog('Priv1004','error','system',str(data.get('user')))
  return {'response': data.get('response'), 'error': 'noprivilege'}
 volinfo = get('vol',data['tenant'])[0]
 data['owner'] = 'leader'
 if 'NFS' not in str(volinfo[0]):     # r5: a tenant that is no NFS volume raised UnboundLocalError (cmndstring), HTTP 500
  return {'response': data.get('response'), 'error': 'notnfs'}
 if 'NFS' in volinfo[0]:
    data['owner'] = volinfo[0].split('/')[2]
    pool = volinfo[0].split('/')[3]
    cmndstring = '/TopStor/TenantDelUser '+leaderip+' '+data['response']+' '+pool+' '+data['tenant']+' '+data['name']
 postchange(cmndstring,data['owner'])
 return data



@app.route('/api/v1/users/UnixAddUser', methods=['GET','POST'])
@login_required
@audit_command
def UnixAddUser(data):
 global allgroups, leaderip
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 # Guards (uservalid.py): name of 3-32 letters/digits/-, not a system account, a real password, and no second
 # user with exactly the same name.  The answer says what happened in 'adduser': 'accepted' or 'rejected: <why>'.
 for field in ('name', 'Password', 'Volpool'):
  if field not in data:
   data['adduser'] = 'rejected: the field '+field+' is missing'
   return data
 # the values as they were sent: login_required removes every blank from the parameters, so a name or a password
 # with a blank would otherwise be accepted as a different one (and the user could not log in with what was typed)
 rawname = request.args.get('name', data.get('name'))
 code, reason = check_new_user_coded(rawname, request.args.get('Password', data.get('Password')))
 if reason:
  # every rejection is reported through logmsg, with a message that says what was wrong
  logmsg.sendlog(code,'error',loggedusers[data['token']]['user'],logname(rawname))
  data['adduser'] = 'rejected: '+reason
  data['response'] = 'rejected'
  return data
 if str(get('usersinfo/'+data['name'])[0]) not in ('_1', '-1', '', 'None'):
  logmsg.sendlog('Unlin1021uu','error',loggedusers[data['token']]['user'],data['name'])
  data['adduser'] = 'rejected: a user with this name already exists'
  data['response'] = 'rejected'
  return data
 pool = data['Volpool']
 if 'NoHome' in data['Volpool'] or '-' in data['Volpool']:
  pool = 'NoHome'
 else:
    isvu =  int(is_valid_ip(data['HomeAddress']))+int(is_unique_ip(data['HomeAddress'],'HOME'))
    if isvu == 0:
        print('ip is valid')
    else:
        if isvu < 100:
            logmsg.sendlog('IPaddrfa','error','system',loggedusers[data['token']]['user'])
            data['adduser'] = 'rejected: invalid IP address'
        elif isvu > 10 and isvu < 120: 
            logmsg.sendlog('IPadduqfa','error','system',loggedusers[data['token']]['user'])
            data['adduser'] = 'rejected: the IP address is already in use'
        else:
            logmsg.sendlog('IPnamuqfa','error','system',loggedusers[data['token']]['user'])
            data['adduser'] = 'rejected: the name is already used'
        data['response'] = 'rejected'
        return data


 if int(is_unique_name(data['name']))==1000:
    logmsg.sendlog('IPnamuqfa','error','system',loggedusers[data['token']]['user'])
    data['adduser'] = 'rejected: the name is already used by a user, a group or a volume'
    return data
    
 grps = data.get('groups') or ''
 groupstr = ''
 allgroups = getgroups()
 groupstr, bad = resolve_groups(grps, allgroups)
 if bad:
  data['adduser'] = 'rejected: invalid group: '+','.join(bad)
  data['response'] = 'rejected'
  return data
 groupstr = with_everyone(groupstr)
 cmndstring = '/TopStor/UnixAddUser '+leaderip+' '+data.get('name')+' '+pool+' groups'+groupstr+' ' \
     +data.get('Password')+' '+data.get('Volsize')+'G '+data.get('HomeAddress')+' '+data.get('HomeSubnet')+' hoststub'+' '+data['user']
 # QSD5.352 r9 (prover D2): the host that owns the home pool; UnixAddUser (on the leader) creates the home there, not on
 # itself (as volumes/create posts to the pool owner)
 if pool != 'NoHome':
  try:
   getalltime()
   cmndstring += ' homeowner='+allinfo['hosts'][allinfo['pools'][pool]['host']]['name']
  except Exception as e:
   print('UnixAddUser: no owner for the home pool', pool, e)
 print('UnixAddUser', mask_text(cmndstring, _request_secrets(data)))
 postchange(cmndstring)
 data['adduser'] = 'accepted'
 return data 

@app.route('/api/v1/volumes/grouplist', methods=['GET'])
@login_required
@audit_command
def api_volumes_groupslist(data):
 global allgroups, allusers
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 thegroup = [] 
 api_users_userslist(data)
 for group in allgroups:
  groupusers = []
  for user in allusers:
   if user['name'] in str(group[2]):
    groupusers.append(user['id'])
  if len(groupusers) < 1:
   groupusers=["NoUser"]
  thegroup.append({'text':group[0], 'id':group[1], 'users':groupusers})
 return jsonify({'results':thegroup})




@app.route('/api/v1/groups/grouplist', methods=['GET'])
@login_required
@audit_command
def api_groups_groupslist(data):
 global allgroups, allusers
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 thegroup = [] 
 api_users_userslist(data)
 for group in allgroups:
 # if group[0] == 'Everyone':
 #  continue

  groupusers = []
  for user in allusers:
   grpusrs = str(group[2]).split(',')
   for grp  in grpusrs:
    if user['name'] == grp and user['id'] not in groupusers:
     groupusers.append(user['id'])
#   if user['name'] in str(group[2]) :
#    groupusers.append(user['id'])
  if len(groupusers) < 1:
   groupusers=["NoUser"]
  thegroup.append({'name':group[0], 'id':group[1], 'users':groupusers})
 return jsonify({'allgroups':thegroup})

@app.route('/api/v1/users/userauths', methods=['GET'])
@login_required
@audit_command
def userauths(data):
 global allgroups, allusers, leaderip
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 if  data['username'] == 'admin':
  return {'auths':'true','response':data['response']}
 userlst = etcdgetjson(leaderip,'usersinfo','--prefix')
 priv = ''    # QSD5.321: an unknown user or a malformed row answers no privileges, not an UnboundLocalError (HTTP 500)
 for user in userlst:
  username = user['name'].replace('usersinfo/','')
  if username == data['username']:
   if not usersinfo_ok(user.get('prop')):
    usersinfo_badrow(username, user.get('prop'))
    break
   priv = '/'.join(user['prop'].split('/')[4:])
   break
 return jsonify({'auths':priv, 'response':data['response']})

@app.route('/api/v1/partners/partnerlist', methods=['GET'])
@login_required
@audit_command
def api_partners_userslist(data):
 global leaderip
 if 'baduser' in data['response']:
  return {'response': 'baduser'}
 allpartners=[]
 partnerlst = etcdgetjson(leaderip,'Partner/','--prefix')
 for partner in partnerlst:
  alias =  partner["name"].split('/')[1] 
  split = partner["prop"].split('/') 
  allpartners.append({'alias': alias, "ip":split[0], "type":split[1], "port":split[2]})
 return { "allpartners":allpartners }

def userhomeinfo(volumes, username):
 # QSD5.339: the home address and subnet of a user come from the user's HOME volume (<user>_<id>); '' when there is none
 for volname, vol in volumes.items():
  if vol.get('prot') in ('HOME', 'HOMEE') and volname.rsplit('_',1)[0] == username:
   addr = str(vol.get('ipaddress', ''))
   if addr in ('NoAddress', '_1'):
    addr = ''
   return addr, str(vol.get('Subnet', '') or '')
 return '', ''

@app.route('/api/v1/users/userlist', methods=['GET'])
@login_required
@audit_command
def api_users_userslist(data):
 global allgroups, allusers, leaderip
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 if 'tenant' not in data:
    data['tenant'] = 'Cluster'
 alldict = dict()
 # QC 609: build the list locally and publish it at the end.  The module global used to be emptied here and refilled
 # while the slow etcd/zfs reads ran (seconds to minutes under load); a groups/groupchange, UnixAddgroup or grouplist arriving
 # in that window mapped the user ids against an empty or partial list and wrote the group back with NO members.
 _newusers = []
 if 'Cluster' not in data['tenant']:
    userlst = get('tenant',data['tenant']+'/users')[0][1].split('/')
    grplst = get('tenant',data['tenant']+'/group')[0][1].split('/')[1]
    grpusrs = grplst.split(':')[-1]
    group = grplst.split(':')[0]
    uid=0
    for user in userlst:
        username = user.split(':')[0]
        if username == '':
            continue
        userid = user.split(':')[1]
        if username in grplst:
            grp = [0] 
        else:
            grp = 'NoGroup'
        _newusers.append({"name":username, 'id':uid, 'userid':userid, "pool":'na', "size":'na', "groups":grp, 'priv':'na'})
        uid += 1
    allusers = _newusers; alldict['allusers'] = _newusers
    alldict['allgroups'] = [[group,0,grpusrs]]
    alldict['usersnohome'] = [] 
    return jsonify(alldict)
 userlst = etcdgetjson(leaderip,'usersinfo','--prefix')
 allgroups = getgroups()
 userdict = dict()
 for group in allgroups:
  groupid = group[1]
  grpusers = group[2].split(',')
  for grpuser in grpusers:
   if grpuser not in userdict:
    userdict[grpuser] = []
   if str(groupid) not in userdict[grpuser]:      # QC 609: a user listed twice in a group record (Everyone) gave a duplicated id
    userdict[grpuser].append(str(groupid))
 usersnohome = []
 nohomeid = 0
 uid = 0
 try:
  getalltime()
  homevols = allinfo['volumes']
 except Exception:
  homevols = {}
 for user in userlst:
  username = user['name'].replace('usersinfo/','')
  if not usersinfo_ok(user.get('prop')):
   usersinfo_badrow(username, user.get('prop'))    # QSD5.321: a malformed row is skipped, not an HTTP 500 for the whole list
   continue
  usersize = user['prop'].split('/')[3]
  userpool = user['prop'].split('/')[1]
  priv = '/'.join(user['prop'].split('/')[4:])
  if username not in userdict:
   groups = ['NoGroup']
  else:
   groups = userdict[username]
  homeaddr, homesub = ('', '') if 'NoHome' in userpool else userhomeinfo(homevols, username)
  _newusers.append({"name":username, 'id':uid, "pool":userpool, "size":usersize, "groups":groups, 'priv':priv, 'HomeAddress':homeaddr, 'HomeSubnet':homesub})
  uid += 1
  if 'NoHome' in userpool:
   usersnohome.append({ 'id':nohomeid, 'text': username })
   nohomeid += 1 
 allusers = _newusers; alldict['allusers'] = _newusers
 alldict['allgroups'] = allgroups
 alldict['usersnohome'] = usersnohome
 return jsonify(alldict)

@app.route('/api/v1/groups/userlist', methods=['GET'])
@login_required
@audit_command
def api_groups_userlist(data):
 global allusers
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 usr = []
 api_users_userslist(data)
 for user in allusers:
  usr.append({'id':user['id'],'text':user['name']})
 return jsonify({'results':usr})


@app.route('/api/v1/users/grouplist', methods=['GET'])
@login_required
@audit_command
def api_users_grouplist(data):
 global allgroups
 if 'baduser' in data['response']:
      return {'response': 'baduser'}
 grp = []
 if 'Cluster' not in data['tenant']:
    allgroups = [get('tenant',data['tenant']+'/group')[0][1].split('/')[1].split(':')[0]]
    for group in allgroups:
        grp.append({'id':0,'text':group})
 else:
    allgroups = getgroups()
    for group in allgroups:
        grp.append({'id':group[1],'text':group[0]})
 return jsonify({'results':grp, 'response':data['response']})


@app.route('/api/v1/pools/actionOnDisk', methods=['GET','POST'])
@login_required
@audit_command
def offlineOrOnlineDisk(data):
    global allinfo, myhost, leaderip
    if 'baduser' in data['response']:
      return {'response': 'baduser'}
    getalltime()
    action = data['action']
    pool = data['pool']
    disk = data['actualdisk'] # "scsi-*" format. 
    #disk = data['actualdisk'] # "sd*" format.
    data['owner'] = allinfo['pools'][pool]['host']
    ownerip = allinfo['hosts'][data['owner']]['ipaddress']
    datastr = myhost + ' ' + data['user'] + ' ' + leaderip + ' ' + action + ' ' + pool + ' ' + disk
    cmndstring = 'python /TopStor/actionOnDisk.py ' + datastr
    postchange(cmndstring,data['owner'])
#    z = cmdline.split(' ')
#    msg = {'req': 'Pumpthis', 'reply':z}
#    sendhost(ownerip, str(msg),'recvreply',myhost)
    return data

@app.route('/api/v1/hosts/getConfig', methods=['GET','POST'])
@login_required
@audit_command
def getNodeConfigFile(data):
    global leaderip, myhost
    if 'baduser' in data['response']:
      return {'response': 'baduser'}
    nodeName = data["nodeName"]
    getConfig(leaderip, nodeName)
    downloadConfig(leaderip, myhost)
    file_path = "/TopStordata/config_" + nodeName + ".txt"
    return send_file(file_path, mimetype='text/plain', as_attachment=True)

@app.route('/api/v1/hosts/getAllConfig', methods=['GET','POST'])
@login_required
@audit_command
def getAllConfigFiles(data):
    global leaderip, readyhosts
    if 'baduser' in data['response']:
      return {'response': 'baduser'}
    hostsready()
    configFiles = []
    zipfilePath = "/TopStordata/All_Configs.zip"
    getConfig(leaderip, myhost)
    downloadConfig(leaderip, myhost)
    for host in readyhosts:
        nodeName = host["name"]
        nodeip = host['ip']
        filePath = "/TopStordata/config_" + nodeName + ".txt"
        configFiles.append((filePath, 'config_'+nodeName + ".txt"))
    with zipfile.ZipFile(zipfilePath, "w") as zipF:
        for file in configFiles:
            zipF.write(file[0], file[1] ,compress_type = zipfile.ZIP_DEFLATED)
    return send_file(zipfilePath, as_attachment=True)

@app.route('/api/v1/software/update', methods=['GET','POST'])
@login_required
@audit_command
def updateSoftware(data):
    if data.get('response') == 'baduser':
        return {'response': 'baduser'}
    # QSD5.352 r2 (validator R4): no privilege check: any logged-in user (e.g. Logs only) could start a download onto the
    # leader, also source-type=local ('cp -r <path>/* /TopStordata/').  The Updates page itself needs Uploadch.
    if not has_privilege('Uploadch', data.get('user')):
        logmsg.sendlog('Priv1004','error','system',str(data.get('user')))
        return {'response': data.get('response'), 'error': 'noprivilege'}

    source_type = data.get('source-type')
    source = data.get('source')
    location = data.get('location')
    version = data.get('version')
    # QSD5.352 (QC 696): the Updates page now posts here (it used software/download/url|share, which do not exist).
    # downloadSoftwareUpdate.sh reads its options by POSITION (--location must be the 7th word, the CIFS user the 9th),
    # so a share without --version shifted --location and the script stopped; such calls are refused with a reason now.
    if source_type not in ('http', 'nfs', 'cifs', 'local'):
        return {'response': data.get('response'), 'error': 'invalidsource', 'message': 'source-type must be http, nfs, cifs or local'}
    if not source or any(c.isspace() for c in str(source)):
        return {'response': data.get('response'), 'error': 'invalidsource', 'message': 'the source is missing or has blanks'}
    if source_type in ('nfs', 'cifs'):
        if not location or not version:
            return {'response': data.get('response'), 'error': 'invalidsource', 'message': source_type+' needs location and version'}
        if source_type == 'cifs' and (not data.get('username') or not data.get('password')):
            return {'response': data.get('response'), 'error': 'invalidsource', 'message': 'cifs needs username and password'}

    command = ['./downloadSoftwareUpdate.sh', f'--source-type {source_type}', f'--source {source}']

    if version:
        command.append(f'--version {version}')

    if source_type == 'cifs':
        username = data.get('username')
        password = data.get('password')
        command.extend([
            f'--location {location}',
            f'--username {username}',
            f'--password {password}'
        ])
    elif source_type == 'nfs':
        command.append(f'--location {location}')

    command_string = ' '.join(command)
    postchange(command_string, 'leader')

    return {'data': mask_text(command_string, _request_secrets(data))}   # QSD5.352: no share password in the answer

@app.route('/api/v1/software/localFileUpdate', methods=['GET','POST'])
@login_required
@audit_command
def localFileUpdate(data):
    if 'baduser' in data['response']:
      return {'response': 'baduser'}
    # QSD5.352 r3 (validator N1): no privilege check: any logged-in user could save an uploaded file into /TopStordata.
    # Same rule as software/update (R4): the Updates page needs Uploadch.  Checked before the upload is read.
    if not has_privilege('Uploadch', data.get('user')):
        logmsg.sendlog('Priv1004','error','system',str(data.get('user')))
        return {'response': data.get('response'), 'error': 'noprivilege'}
    
    uploaded_file = request.files['file']
    if uploaded_file.filename != '':
        filename = upload_name(uploaded_file.filename)     # QSD5.352 r4 (validator N2): base name only, never outside /TopStordata
        # QSD5.352 r5 (validator N3): saved in /TopStordata/uploads, never over a /TopStordata file; a symlink is refused
        filePath = save_upload(uploaded_file, filename) if filename is not None else None
        if filePath is None:
            logmsg.sendlog('Unlin1026', 'error', str(data.get('user')))
            return {'response': data.get('response'), 'error': 'badfilename'}
        return {"data": 'success'}
    return {"data": uploaded_file.filename}


@app.route('/api/v1/telemetry/heartbeat', methods=['POST', 'GET'])
def telemetry_heartbeat():
    # Write the current epoch time to a file
    try:
        with open('/tmp/ui_active_heartbeat', 'w') as f:
            f.write(str(int(time.time())))
        return {"status": "boost_active"}, 200
    except Exception as e:
        return {"error": str(e)}, 500


@app.route('/api/v1/info/summary', methods=['GET', 'POST'])
def get_service_summary():
    global leaderip # Use the globally defined leaderip from fapi.py
    
    try:
        # 1. Users and Groups (JSON data)
        # fapi.py native approach: etcdgetjson(leaderip, 'usersinfo', '--prefix')
        users_data = etcdgetjson(leaderip, 'usersinfo', '--prefix')
        users_count = len(users_data) if isinstance(users_data, list) else 0

        groups_data = etcdgetjson(leaderip, 'usersigroup', '--prefix')
        groups_count = len(groups_data) if isinstance(groups_data, list) else 0

        # 2. Pools (Standard data)
        # fapi.py native approach: get('pools/','--prefix')
        pools_data = get('pools/', '--prefix')
        pools_count = len(pools_data) if isinstance(pools_data, list) else 0

        # 3. Categorize Volumes (Standard data)
        # fapi.py native approach: get('vol', '--prefix')
        cifs_count = 0
        nfs_count = 0
        iscsi_count = 0

        volumes_data = get('vol', '--prefix')
        if isinstance(volumes_data, list):
            for vol in volumes_data:
                # vol is a tuple e.g., ('vol/NFS/poolname/volname', 'active')
                if isinstance(vol, (list, tuple)) and len(vol) > 0:
                    key = str(vol[0]).upper()
                    if '/CIFS' in key:
                        cifs_count += 1
                    elif '/NFS' in key:
                        nfs_count += 1
                    elif '/ISCSI' in key:
                        iscsi_count += 1

        # 4. Return the exact JSON structure React expects
        return jsonify({
            "users": users_count,
            "groups": groups_count,
            "pools": pools_count,
            "volumes": {
                "cifs": cifs_count,
                "nfs": nfs_count,
                "iscsi": iscsi_count
            }
        }), 200

    except Exception as e:
        print(f"Telemetry Summary Error: {traceback.format_exc()}")
        return jsonify({"error": str(e)}), 500
  
leaderip =0 
myhost=0
if __name__=='__main__':
    #leader = sys.argv[2]
    #leaderip = sys.argv[1]
    # start-up log: one line per step with the seconds since the process started (/TopStordata/fapistart.log,
    # rewritten at every start).  It answers "why did the API take N seconds to come back after a take over".
    import time as _t
    _t0 = _FAPI_T0
    def _mark(step):
        try:
            with open('/TopStordata/fapistart.log', 'a') as f:
                f.write('%s +%.1fs %s\n' % (_t.strftime('%H:%M:%S', _t.gmtime()), _t.time()-_t0, step))
        except Exception:
            pass
    try:
        open('/TopStordata/fapistart.log', 'w').close()
    except Exception:
        pass
    _mark('imports done (interpreter started at '+_t.strftime('%H:%M:%S', _t.gmtime(_FAPI_T0))+')')
    leaderip = get('leaderip')[0]
    myhost = get('clusternode')[0]
    myhostip = get('clusternodeip')[0]
    leader = get('leader')[0]
    _mark('leaderip, clusternode, clusternodeip, leader read from etcd')
    logmsg.initlog(leaderip,myhost)
    initallphy(leaderip)
    _mark('logmsg.initlog + initallphy')
    #myhost = sys.argv[2]
    getalltime()
    _mark('getalltime (disks, pools, volumes) -- starting the web server now')
   #myhostip = sys.argv[5]
    app.run(host="0.0.0.0", port=5001, debug=False, use_debugger=False, use_reloader=False)


