#!/usr/bin/python3
# uservalid.py -- the rules a NEW user must meet.  One place for all callers:
#   fapi.py            from uservalid import check_new_user          (the API answers at once)
#   UnixAddUser        /TopStor/uservalid.py <name> <password>       (also covers the bulk upload, which calls the script)
# check_new_user() returns '' when the pair is acceptable, otherwise the reason as text.
# The command line prints the reason and exits 1 when the user must not be created.
# Sync copies of an existing user (UnixAddUser ... pullsync) are NOT checked: they repeat what the leader accepted.
import re, sys

NAME_MIN, NAME_MAX = 3, 32
PASS_MIN, PASS_MAX = 3, 128

# Accounts of the system and of the appliance.  UnixAddUser runs "userdel -f <name>" before it creates
# the user, so one of these names would delete a system account.
RESERVED = {
 'root','admin','bin','daemon','adm','lp','sync','shutdown','halt','mail','operator','games','ftp','nobody',
 'dbus','polkitd','sshd','chrony','tss','rpc','rpcuser','nfsnobody','postfix','apache','nginx','named','tcpdump',
 'docker','etcd','grafana','prometheus','systemd','wheel','users','nogroup','guest','samba','smb',
}

def check_username(name):
    name = '' if name is None else str(name)
    if name == '':
        return 'the user name is empty'
    if len(name) < NAME_MIN:
        return 'the user name is shorter than %d characters' % NAME_MIN
    if len(name) > NAME_MAX:
        return 'the user name is longer than %d characters' % NAME_MAX
    # letters, digits and '-' only, starting with a letter.  No '_' (the sync request is split on it, the
    # other nodes would create the wrong user), no '.', '/', ':' or blanks (they break the scripts and the etcd keys).
    if not re.match(r'^[A-Za-z][A-Za-z0-9-]*$', name):
        return 'the user name may hold letters, digits and - only, and must start with a letter'
    if name.lower() in RESERVED or name.lower().startswith('systemd-'):
        return 'the user name is reserved for the system'
    return ''

def check_password(password):
    password = '' if password is None else str(password)
    if password == '':
        return 'the password is empty'
    if len(password) < PASS_MIN:
        return 'the password is shorter than %d characters' % PASS_MIN
    if len(password) > PASS_MAX:
        return 'the password is longer than %d characters' % PASS_MAX
    if re.search(r'\s', password):
        return 'the password must not contain blanks'
    # characters the shell scripts behind the API would expand or mis-split
    if re.search(r'''['"`\\*?\[\]]''', password):
        return 'the password must not contain quotes, back slashes, * ? [ or ]'
    return ''

def check_new_user(name, password):
    return check_username(name) or check_password(password)

if __name__ == '__main__':
    name = sys.argv[1] if len(sys.argv) > 1 else ''
    password = sys.argv[2] if len(sys.argv) > 2 else ''
    reason = check_new_user(name, password)
    if reason:
        print(reason)
        sys.exit(1)
    sys.exit(0)
