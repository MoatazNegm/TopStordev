#!/usr/bin/python3
# QSD5.347: UnixAddUser gave 'useradd -p' the CLEAR password (the option takes an encrypted value), so /etc/shadow of every
# node held each TopStor user's password in clear text (the share containers bind-mount it).  New users get '!' (UnixAddUser).
# This runs once per node (mark file /root/.shadow-masked, started by topstorrecvreply.py) and sets '!' for the users made
# before: a TopStor user (/etc/passwd comment 'TopStor<hash>', not 'TopStorGroup...') whose shadow field is not already
# locked ('!' / '*' first) or a real crypt hash ('$' first).  Nothing logs in with that field (nologin shell, the API checks
# usershash/<user>, samba has its own database), so locking it changes no login.
#   shadowscrub.py          -> once (does nothing when the mark file is there)
#   shadowscrub.py --check  -> prints how many TopStor users still have a clear field, changes nothing
import os
import subprocess
import sys

MARK = '/root/.shadow-masked'


def clear_users(passwd='/etc/passwd', shadow='/etc/shadow'):
    users = set()
    with open(passwd) as f:
        for line in f:
            p = line.rstrip('\n').split(':')
            if len(p) > 4 and p[4].startswith('TopStor') and not p[4].startswith('TopStorGroup'):
                users.add(p[0])
    out = []
    with open(shadow) as f:
        for line in f:
            p = line.rstrip('\n').split(':')
            if len(p) > 1 and p[0] in users and p[1] != '' and p[1][0] not in '!*$':
                out.append(p[0])
    return out


def scrub(passwd='/etc/passwd', shadow='/etc/shadow', usermod='usermod'):
    done = []
    for u in clear_users(passwd, shadow):
        if subprocess.run([usermod, '-p', '!', u], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
            done.append(u)
    return done


def scrub_once():
    try:
        if os.path.exists(MARK):
            return None
        done = scrub()
        with open(MARK, 'w') as f:
            f.write('shadow field of %d TopStor user(s) set to ! by QSD5.347 (it held the clear password)\n' % len(done))
        return done
    except Exception:
        return None


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--check':
        print(len(clear_users()))
    else:
        scrub_once()
