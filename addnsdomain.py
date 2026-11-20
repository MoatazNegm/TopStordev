#!/usr/bin/python3
# addnsdomain.py <AD server address> [timeout seconds]
# QSD5.352 r10r (QC 587.1, r10p and r10q): prints the DNS domain of the Active Directory that answers on the address
# (lower case, e.g. 'qc.local'), read from the anonymous LDAP root DSE (defaultNamingContext DC=qc,DC=local), and exits 0;
# prints nothing and exits 1 when the server does not answer or the answer has no naming context.
# Why: a domain share made with the short (NetBIOS) AD name 'QC' started the share image (membersmb) with
# DOMAIN_NAME=QC, so krb5.conf default_realm and smb.conf 'realm' were 'QC'.  'realm join' (by the server address)
# worked, but 'kinit Administrator@QC' and 'net ads join' failed (NT_STATUS_NO_LOGON_SERVERS) and Samba could not find
# a DC for realm 'QC' ('ads_find_dc: name resolution for realm QC failed'), so every domain user was refused by the share.
# cifs.sh now gives the image the real DNS domain when a short name was typed and it is the domain's first label.
# No libraries: one LDAP SearchRequest (base '', scope base, filter (objectClass=*)) encoded by hand.
import re
import socket
import sys


def tlv(tag, body):
    n = len(body)
    if n < 0x80:
        ln = bytes([n])
    elif n < 0x100:
        ln = bytes([0x81, n])
    else:
        ln = bytes([0x82, n >> 8, n & 0xff])
    return bytes([tag]) + ln + body


def request():
    attrs = tlv(0x30, tlv(0x04, b'defaultNamingContext'))
    search = tlv(0x63, tlv(0x04, b'') + tlv(0x0a, b'\x00') + tlv(0x0a, b'\x00') + tlv(0x02, b'\x00') +
                 tlv(0x02, b'\x00') + tlv(0x01, b'\x00') + tlv(0x87, b'objectClass') + attrs)
    return tlv(0x30, tlv(0x02, b'\x01') + search)


def length(data, i):
    # BER length at data[i]: (value length, index of the first value byte); (-1, i) when cut short
    if i >= len(data):
        return -1, i
    n = data[i]
    if n < 0x80:
        return n, i + 1
    k = n & 0x7f
    if k == 0 or i + 1 + k > len(data):
        return -1, i
    return int.from_bytes(data[i + 1:i + 1 + k], 'big'), i + 1 + k


def dnsdomain(data):
    # the attribute name, then SET OF { OCTET STRING value }: read the value by its BER length (the next byte after the
    # value is a new tag, often 0x30 = '0', so a pattern match alone would take it in)
    i = data.find(b'defaultNamingContext')
    if i < 0:
        return ''
    i += len(b'defaultNamingContext')
    if i >= len(data) or data[i] != 0x31:
        return ''
    n, i = length(data, i + 1)
    if n < 0 or i >= len(data) or data[i] != 0x04:
        return ''
    n, i = length(data, i + 1)
    if n <= 0 or i + n > len(data):
        return ''
    dn = data[i:i + n].decode('utf-8', 'replace')
    parts = [p.split('=', 1)[1] for p in dn.split(',') if p.strip().upper().startswith('DC=') and '=' in p]
    if not parts or not all(re.match(r'^[A-Za-z0-9-]+$', p.strip()) for p in parts):
        return ''
    return '.'.join(p.strip() for p in parts).lower()


def complete(data):
    # True when the reply holds a whole SearchResultDone message (protocolOp tag 0x65), read message by message with
    # the BER lengths; False while a message is still cut short (r10r validator G-7: the loop ended when the first TCP
    # piece happened to end near an ASCII 'e' = 0x65 of the reply, then the name was not read and the typed name was kept)
    i = 0
    while i < len(data):
        if data[i] != 0x30:
            return True                      # not LDAP: stop reading, dnsdomain() decides
        n, j = length(data, i + 1)
        if n < 0 or j + n > len(data):
            return False
        if j < len(data) and data[j] == 0x02:
            m, k = length(data, j + 1)
            if m >= 0 and k + m < j + n and data[k + m] == 0x65:
                return True
        i = j + n
    return False


def main():
    if len(sys.argv) < 2:
        return 1
    host = sys.argv[1]
    tmo = float(sys.argv[2]) if len(sys.argv) > 2 else 5.0
    try:
        s = socket.create_connection((host, 389), timeout=tmo)
        s.settimeout(tmo)
        s.sendall(request())
        data = b''
        while not complete(data) and len(data) < 65536:
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
            if dnsdomain(data):
                break
        s.close()
    except Exception:
        return 1
    dom = dnsdomain(data)
    if not dom:
        return 1
    print(dom)
    return 0


if __name__ == '__main__':
    sys.exit(main())
