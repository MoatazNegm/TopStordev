#!/usr/bin/python3
# QSD5.347: UnixAddUser gave 'useradd -p' the CLEAR password (the option takes an encrypted value), so /etc/shadow of every
# node held each TopStor user's password in clear text (the share containers bind-mount it).  New users get '!' (UnixAddUser).
# QSD5.348: UnixChangePass did the same with 'usermod -p' on every password change (admin included) and the copies of the
# table kept the old text: /etc/shadow- (the backup usermod/useradd write, the state before their change) and
# /opt/passwds/shadow (UnixAddGroup's hard link 'ln -f /etc/shadow ...': usermod/useradd replace /etc/shadow by rename, so the
# link keeps the OLD inode).  This is now a cheap check that runs on every start of topstorrecvreply.py and after each
# password change (UnixChangePass); it changes nothing when everything is clean.  A field is "clear" when it is not empty
# and does not start with '!' / '*' (locked) or '$' (a crypt hash).
#   - TopStor user (/etc/passwd comment 'TopStor<hash>', not 'TopStorGroup...') with a clear field -> 'usermod -p !'.
#     Nothing logs in with that field (nologin shell, the API checks usershash/<user>, samba has its own database).
#   - admin (comment 'AdminStor<hash>') with a clear field -> the field IS the password the old UnixChangePass put there:
#     it becomes a SHA-512 crypt hash of that text ('chpasswd -c SHA512', name:password on stdin, never on a command line),
#     so admin keeps a working unix password and the text is gone.
#   - /etc/shadow- with a clear field of such a user (also of one in /etc/passwd- only) -> rewritten as a copy of /etc/shadow.
#   - /opt/passwds/shadow when it exists and is not the same file as /etc/shadow -> linked again (as UnixAddGroup does).
#   shadowscrub.py          -> check and clean (the mark file /root/.shadow-masked: made at the first check, one more line
#                              each time something was changed)
#   shadowscrub.py --check  -> prints how many clear fields are left in /etc/shadow, /etc/shadow- and /opt/passwds/shadow
#                              together (one number), changes nothing
#   shadowscrub.py --detail -> the same per file: 'shadow=<n> shadow-=<n> opt=<n> admin=<n>' (admin = of the shadow count)
import os
import shutil
import subprocess
import sys

MARK = '/root/.shadow-masked'
SHADOW = '/etc/shadow'
BACKUP = '/etc/shadow-'
OPTSHADOW = '/opt/passwds/shadow'


def is_clear(field):
    return field != '' and field[0] not in '!*$'


def kinds(passwd='/etc/passwd', extra=()):
    """user -> 'user' (TopStor user) or 'admin' (AdminStor), read from passwd and the optional extra passwd files"""
    out = {}
    for path in (passwd,) + tuple(extra):
        try:
            with open(path) as f:
                for line in f:
                    p = line.rstrip('\n').split(':')
                    if len(p) < 5 or p[0] in out:
                        continue
                    if p[4].startswith('AdminStor'):
                        out[p[0]] = 'admin'
                    elif p[4].startswith('TopStor') and not p[4].startswith('TopStorGroup'):
                        out[p[0]] = 'user'
        except (FileNotFoundError, PermissionError):
            pass
    return out


def clear_fields(shadow, users):
    """[(user, kind)] of the users whose field in this shadow file is clear (missing file: [])"""
    out = []
    try:
        with open(shadow) as f:
            for line in f:
                p = line.rstrip('\n').split(':')
                if len(p) > 1 and p[0] in users and is_clear(p[1]):
                    out.append((p[0], users[p[0]]))
    except (FileNotFoundError, PermissionError):
        pass
    return out


def field_of(shadow, user):
    with open(shadow) as f:
        for line in f:
            p = line.rstrip('\n').split(':')
            if len(p) > 1 and p[0] == user:
                return p[1]
    return None


def clear_users(passwd='/etc/passwd', shadow=SHADOW):
    """QSD5.347 interface: names with a clear field in shadow (TopStor users and admin)"""
    return [u for u, k in clear_fields(shadow, kinds(passwd))]


def same_file(a, b):
    try:
        sa, sb = os.stat(a), os.stat(b)
        return (sa.st_dev, sa.st_ino) == (sb.st_dev, sb.st_ino)
    except FileNotFoundError:
        return False


def relink(src, dst):
    """dst becomes a hard link of src (rename over it, so there is no moment without dst); a copy when no link is possible"""
    tmp = dst + '.shadowscrub'
    try:
        os.unlink(tmp)
    except FileNotFoundError:
        pass
    try:
        os.link(src, tmp)
    except OSError:
        shutil.copy2(src, tmp)
    os.replace(tmp, dst)


def scrub(passwd='/etc/passwd', shadow=SHADOW, usermod='usermod', chpasswd='chpasswd', backup=None, optshadow=None):
    """clean shadow, then the backup and the hard-link copy; returns a list of what was changed (empty: nothing to do)"""
    done = []
    users = kinds(passwd)
    for u, k in clear_fields(shadow, users):
        if k == 'admin':
            pw = field_of(shadow, u)
            r = subprocess.run([chpasswd, '-c', 'SHA512'], input=('%s:%s\n' % (u, pw)).encode(),
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            r = subprocess.run([usermod, '-p', '!', u], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if r.returncode == 0:
            done.append(u)
    if backup is not None and os.path.exists(backup):
        busers = kinds(passwd, (passwd + '-',))
        if clear_fields(backup, busers):
            # the backup becomes a copy of the clean table, written in place (its inode, mode, owner and SELinux label stay)
            with open(shadow, 'rb') as f:
                data = f.read()
            with open(backup, 'r+b') as f:
                f.write(data)
                f.truncate()
            done.append(backup)
    if optshadow is not None and os.path.exists(optshadow) and not same_file(shadow, optshadow):
        relink(shadow, optshadow)
        done.append(optshadow)
    return done


def counts(passwd='/etc/passwd', shadow=SHADOW, backup=BACKUP, optshadow=OPTSHADOW):
    users = kinds(passwd)
    s = clear_fields(shadow, users)
    b = clear_fields(backup, kinds(passwd, (passwd + '-',)))
    o = clear_fields(optshadow, kinds(passwd, (passwd + '-',))) if os.path.exists(optshadow) else []
    return {'shadow': len(s), 'shadow-': len(b), 'opt': len(o), 'admin': len([1 for u, k in s if k == 'admin'])}


def scrub_check():
    """every start: clean when needed (cheap when clean); never raises"""
    try:
        done = scrub(backup=BACKUP, optshadow=OPTSHADOW)
        if not done and not os.path.exists(MARK):
            with open(MARK, 'w') as f:
                f.write('QSD5.348: shadow checked, nothing to change\n')
        elif done:
            with open(MARK, 'a') as f:
                f.write('QSD5.348: %d change(s): %d user field(s) (clear password) locked or hashed%s%s\n' % (
                    len(done), len([d for d in done if not d.startswith('/')]),
                    ', /etc/shadow- rewritten' if BACKUP in done else '',
                    ', /opt/passwds/shadow linked again' if OPTSHADOW in done else ''))
        return done
    except Exception:
        return None


scrub_once = scrub_check      # QSD5.347 name (topstorrecvreply.py of that version)


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--check':
        c = counts()
        print(c['shadow'] + c['shadow-'] + c['opt'])
    elif len(sys.argv) > 1 and sys.argv[1] == '--detail':
        c = counts()
        print('shadow=%d shadow-=%d opt=%d admin=%d' % (c['shadow'], c['shadow-'], c['opt'], c['admin']))
    else:
        scrub_check()
