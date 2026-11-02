#!/usr/bin/python3
# QSD5.344: keep passwords, CHAP secrets and partner pass phrases out of node files, logs, the command log and API answers
# (QC tests 701, 674, 704).  One place that knows which request fields are secrets and how a secret is masked.
#   is_secret_key(k)          True for a request field that carries a secret (Password, password, chappas, dompass, phrase ...)
#   secret_values(d)          the secret values of a request dict (also the value as typed, before login_required removed blanks)
#   mask_text(text, values)   text with every secret value replaced by MASK
#   masked(d)                 a copy of a dict with every secret field set to MASK (for debug files and the queue)
# The executors still receive the real value on their command line (the message bus format is unchanged); only what is
# WRITTEN somewhere for people to read is masked.
import re

MASK = '****'
# exact field names (lower case) that are secrets; any field whose name contains 'pass' or 'phrase' is one too
SECRET_KEYS = {'password', 'pass', 'passwd', 'newpass', 'oldpass', 'userpass', 'chappas', 'chappass', 'chapsecret',
               'dompass', 'phrase', 'passphrase', 'secret', 'adminpass'}
MIN_LEN = 3          # shorter values are not masked inside free text (they would mask unrelated words)


def is_secret_key(key):
    k = str(key).lower()
    return k in SECRET_KEYS or 'pass' in k or 'phrase' in k


def secret_values(d, extra=()):
    vals = set()
    try:
        items = list(d.items())
    except AttributeError:
        items = []
    for k, v in items:
        if is_secret_key(k) and v is not None:
            v = str(v)
            if len(v) >= MIN_LEN:
                vals.add(v)
            nb = v.replace(' ', '')
            if len(nb) >= MIN_LEN:
                vals.add(nb)
    for v in extra:
        if v is not None and len(str(v)) >= MIN_LEN:
            vals.add(str(v))
    return sorted(vals, key=len, reverse=True)      # longest first: a secret that contains another one is masked whole


def mask_text(text, values):
    text = str(text)
    for v in values:
        if v:
            text = text.replace(v, MASK)
    return text


_QUERY_RE = None

def mask_query(text):
    """QSD5.345: the values of secret query parameters in a request line / URL (token, any name with pass, phrase, secret
    or chap in it, the SECRET_KEYS) become ****.  The web server's access log prints the whole request line, and the UI and
    API keys send the login token (and some forms their passwords) in the query string (QX-233 step 4)."""
    global _QUERY_RE
    import re
    if _QUERY_RE is None:
        names = '|'.join(sorted((re.escape(k) for k in SECRET_KEYS), key=len, reverse=True))
        _QUERY_RE = re.compile(r'([?&;](?:token|apikey|key|' + names + r'|[A-Za-z0-9_.-]*(?:pass|phrase|secret|chap)[A-Za-z0-9_.-]*)=)[^&;\s"\']*',
                               re.IGNORECASE)
    return _QUERY_RE.sub(lambda m: m.group(1) + MASK, str(text))


def masked(d):
    try:
        return {k: (MASK if is_secret_key(k) and v not in (None, '') else v) for k, v in d.items()}
    except AttributeError:
        return d


# ---- partner pass phrase at rest (etcd Partner/<alias>_<type> = ip/type/port/<phrase>) -------------------------------
# The phrase is needed again later (key exchange with the partner), so it cannot be a hash.  It is stored encrypted, the
# same way as usershash (openssl aes-256-ctr, pbkdf2), as 'enc~' + url-safe base64 without '/' (the value is split on '/').
# A value without the 'enc~' prefix is a clear phrase of an older version and is used as it is.
import subprocess

PHRASE_PREFIX = 'enc~'


def _phrase_key(alias):
    # one key for every partner: the readers name the partner in different forms (alias, alias_Receiver, ...), so the
    # alias is not part of the key (the protection is the one of usershash: not readable at a glance, not a vault)
    return '#skMe22partner'


def _env(alias):
    import os
    env = dict(os.environ)
    env['TSPHRASEKEY'] = _phrase_key(alias)      # in the environment, not on the command line (ps would show it)
    return env


def phrase_encrypt(alias, phrase):
    phrase = str(phrase)
    r = subprocess.run(['openssl', 'enc', '-e', '-aes-256-ctr', '-pbkdf2', '-base64', '-A', '-pass', 'env:TSPHRASEKEY'],
                       input=phrase.encode(), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=20,
                       env=_env(alias))
    out = r.stdout.decode().strip()
    if r.returncode != 0 or not out:
        raise RuntimeError('phrase_encrypt failed')
    return PHRASE_PREFIX + out.replace('+', '-').replace('/', '_').replace('=', '')


def phrase_decrypt(alias, value):
    value = str(value)
    if not value.startswith(PHRASE_PREFIX):
        return value
    b = value[len(PHRASE_PREFIX):].replace('-', '+').replace('_', '/')
    b += '=' * (-len(b) % 4)
    r = subprocess.run(['openssl', 'enc', '-d', '-aes-256-ctr', '-pbkdf2', '-base64', '-A', '-pass', 'env:TSPHRASEKEY'],
                       input=(b + '\n').encode(), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=20,
                       env=_env(alias))
    if r.returncode != 0:
        return value            # not ours (a clear phrase that happens to start with the prefix): used as it is
    try:
        return r.stdout.decode()
    except UnicodeDecodeError:
        return value


# ---- message bus logs (QSD5.347) ---------------------------------------------------------------------------------------
# Every message of the 'recvreply' queue is a dict {'req': ..., 'reply': [command, arg1, ...]}; the receiving node
# (topstorrecvreply.py, actionreply.py) writes its body to /root/recvreply, /root/recv, /root/recvpump ... for debugging.
# The command of 'Add User' (UnixAddUser) carries the new user's password as argument 5, so the clear password stayed in
# those files on the leader (QSD5.346 proof, QX-221 step 4).  The executors still get the real values; what is WRITTEN is:
#   1. the masked copy of the arguments the sender made (sendhost(..., logreq=...) puts it into the message as 'logreply',
#      fapi.postchange masks the request's own secrets, the key exchange masks the pass phrase), and on top of it
#   2. a fixed list of commands whose arguments are secrets (also for a sender of an older version without 'logreply').
# BUS_SECRET_ARGS: command name -> positions of secret arguments, counted from the command (+n) or from the end (-n).
BUS_SECRET_ARGS = {
    'UnixAddUser': (5,),              # leaderip name pool groups PASSWORD size addr subnet hoststub user
    'PartnerAdd.py': (5,),            # ip alias type port PHRASE user [init]
    'UsersMassAddition.py': (5,),     # leaderip user myhost file TOKEN (the login token of the upload)
    'receivekeys.sh': (-2,),          # ... PHRASE keys
    'sendreceivekeys.py': (-2,),      # ... PHRASE keys
}
BUS_SECRET_FLAGS = ('--password',)   # software update from a CIFS share: '--password' <value>
BUS_LOG_FILES = ('/root/recvreply', '/root/recv', '/root/recvpump', '/root/recv2', '/root/recvVolumeChange',
                 '/root/recvVlumeCreate')
BUS_SCRUB_MARK = '/root/.buslogs-masked'


def mask_bus_reply(reply):
    """A copy of a bus command (list) with the secret arguments of BUS_SECRET_ARGS / BUS_SECRET_FLAGS masked."""
    if not isinstance(reply, (list, tuple)):
        return reply
    out = list(reply)
    n = len(out)
    for i, a in enumerate(reply):
        if not isinstance(a, str):
            continue
        offs = BUS_SECRET_ARGS.get(a.rsplit('/', 1)[-1])
        if offs:
            for off in offs:
                j = i + off if off > 0 else n + off
                if i < j < n and isinstance(out[j], str) and out[j] != '':
                    out[j] = MASK
        if a in BUS_SECRET_FLAGS and i + 1 < n and isinstance(out[i + 1], str) and out[i + 1] != '':
            out[i + 1] = MASK
    return out


def bus_log_reply(r):
    """What may be written of the 'reply' of a parsed bus message r: the sender's masked copy ('logreply') when it fits,
    else the reply, then the fixed list on top."""
    rep = r.get('reply') if isinstance(r, dict) else None
    lr = r.get('logreply') if isinstance(r, dict) else None
    if isinstance(lr, (list, tuple)) and isinstance(rep, (list, tuple)) and len(lr) == len(rep):
        rep = lr
    return mask_bus_reply(rep)


def parse_bus(body):
    """The bus message as a dict (the two ways actionreply.py reads it), or None."""
    from ast import literal_eval
    if isinstance(body, bytes):
        body = body.decode('utf-8', 'replace')
    body = str(body)
    for text in (body, body.replace("'", '"')):
        try:
            r = literal_eval(text)
            if isinstance(r, dict):
                return r
        except Exception:
            pass
    return None


def bus_log_text(body):
    """The text to write for a bus message body: the dict without 'logreply', the reply masked.  A body that cannot be
    read is not written at all (only its size), it could carry anything."""
    r = parse_bus(body)
    if r is None:
        return '<message not readable, ' + str(len(body)) + ' bytes>'
    shown = {k: v for k, v in r.items() if k != 'logreply'}
    if 'reply' in shown:
        shown['reply'] = bus_log_reply(r)
    return str(shown)


def with_logreply(req, logreq):
    """sendhost: the message text req with the sender's masked copy of the reply added as 'logreply' (only when logreq is
    a message of the same shape whose reply differs); anything else returns req unchanged."""
    try:
        d = parse_bus(str(req))
        lr = parse_bus(str(logreq))
        if d is None or lr is None or 'logreply' in d:
            return str(req)
        rep, lrep = d.get('reply'), lr.get('reply')
        if isinstance(rep, list) and isinstance(lrep, list) and len(rep) == len(lrep) and rep != lrep:
            d['logreply'] = lrep
            return str(d)
    except Exception:
        pass
    return str(req)


def bus_scrub_once():
    """Once per node: the bus logs written before QSD5.347 hold clear passwords; they are emptied (the files stay) and a
    mark file says it was done.  Errors are ignored (a debug file is not worth a failed receiver)."""
    import os
    try:
        if os.path.exists(BUS_SCRUB_MARK):
            return False
        for f in BUS_LOG_FILES:
            if os.path.exists(f):
                with open(f, 'w') as fh:
                    fh.write('')
        with open(BUS_SCRUB_MARK, 'w') as fh:
            fh.write('bus logs emptied by QSD5.347 (they held clear passwords); messages are masked from now on\n')
        return True
    except Exception:
        return False


if __name__ == '__main__':
    # shell use:  secretmask.py phrasedec <alias> <stored value>   -> prints the clear phrase (no newline)
    #             secretmask.py phraseenc <alias> <phrase>         -> prints the stored form
    #             secretmask.py maskargs <index> <arg1> <arg2> ...  -> prints the arguments with argument <index> (1-based) masked
    import sys
    if len(sys.argv) >= 4 and sys.argv[1] == 'phrasedec':
        sys.stdout.write(phrase_decrypt(sys.argv[2], sys.argv[3]))
    elif len(sys.argv) >= 4 and sys.argv[1] == 'phraseenc':
        sys.stdout.write(phrase_encrypt(sys.argv[2], sys.argv[3]))
    elif len(sys.argv) >= 3 and sys.argv[1] == 'maskargs':
        idx = [int(x) for x in sys.argv[2].split(',') if x.isdigit()]
        args = sys.argv[3:]
        print(' '.join(MASK if (i + 1) in idx else a for i, a in enumerate(args)))
    else:
        sys.exit(2)
