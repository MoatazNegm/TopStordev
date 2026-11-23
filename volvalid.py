#!/usr/bin/python3
# volvalid.py -- the rule a NEW volume name must meet (CIFS, CIFSdom, NFS, ISCSI, HOME, S3).  One place for all callers:
#   fapi.py            from volvalid import check_volname_coded       (volumes/create answers HTTP 400 at once)
#   scripts            /TopStor/volvalid.py <name>                     (prints "<code>|<reason>" and exits 1 when refused)
# The name becomes the dataset <pool>/<name>_<id>, the container, smb and etcd names and an unquoted word of the
# scripts (split on blanks, used in sed "s/Rname/<name>/"), so only letters, digits, _ and - pass, the first one a
# letter or a digit (no option-like "-x", no ".", "..", "/", ";", ":", blanks, tabs or new lines), at most 32.
# A home (users/UnixAddUser) is named after its user: uservalid.py already keeps that name inside this rule.
import re, sys

NAME_MAX = 32
CODE_NAME = 'Volnam01'     # msgsglobal.txt

def check_volname(name):
    # '' when acceptable, otherwise the reason (the API answer's 'message')
    name = '' if name is None else str(name)
    if name == '':
        return 'the volume name is empty'
    if len(name) > NAME_MAX:
        return 'parameter too long (max %d): the volume name has %d characters' % (NAME_MAX, len(name))
    if not re.match(r'^[A-Za-z0-9][A-Za-z0-9_-]*$', name):
        return 'invalid character in volume name: only letters, digits, _ and - (must start with a letter or digit)'
    return ''

def check_volname_coded(name):
    # ('', '') when acceptable, otherwise (log message code, reason)
    reason = check_volname(name)
    return (CODE_NAME, reason) if reason else ('', '')

def logname(name):
    # the name as it may go into a log message: one word, harmless characters only
    name = re.sub(r'[^A-Za-z0-9_.-]', '.', '' if name is None else str(name))[:32]
    return name or 'noname'

if __name__ == '__main__':
    code, reason = check_volname_coded(sys.argv[1] if len(sys.argv) > 1 else '')
    if reason:
        print(code+'|'+reason)
        sys.exit(1)
    sys.exit(0)
