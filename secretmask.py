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
