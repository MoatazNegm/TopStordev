#!/usr/bin/python3
# nfsportmap.py <volume ip> <nfs container>
# rpcbind inside the NFS container is behind docker's DNAT and answers GETADDR (v3/v4) with the container's private
# 172.17.x.x, so showmount / rpcinfo hung there. This answers on <ip>:111 instead (tcp+udp) with portmap v2 only:
# libtirpc then falls back from v4/v3 (PROG_MISMATCH 2..2) to GETPORT, which carries a port and no address.
# Ports are the fixed ones of nfsd.sh. It exits when the container is gone.
import socket, struct, subprocess, sys, threading, time

ip, cont = sys.argv[1], sys.argv[2]
PORTS = {(100000, 6): 111, (100000, 17): 111, (100005, 6): 20048, (100003, 6): 2049}
DUMP = ((100000, 2, 6, 111), (100000, 2, 17, 111), (100005, 3, 6, 20048), (100003, 4, 6, 2049))

def reply(req):
    if len(req) < 24:
        return None
    xid, mtype, rpcvers, prog, vers, proc = struct.unpack('>IIIIII', req[:24])
    if mtype != 0:
        return None
    head = struct.pack('>IIIII', xid, 1, 0, 0, 0)
    if prog != 100000:
        return head + struct.pack('>I', 1)
    if vers != 2:
        return head + struct.pack('>III', 2, 2, 2)
    if proc == 0:
        return head + struct.pack('>I', 0)
    if proc == 3:
        # cred and verf are flavor, len, body; then prog vers prot port
        off = 24
        for _ in range(2):
            ln = struct.unpack('>I', req[off + 4:off + 8])[0]
            off += 8 + ((ln + 3) & ~3)
        p, v, prot, _ = struct.unpack('>IIII', req[off:off + 16])
        return head + struct.pack('>II', 0, PORTS.get((p, prot), 0))
    if proc == 4:
        body = b''.join(struct.pack('>IIIII', 1, p, v, prot, port) for p, v, prot, port in DUMP)
        return head + struct.pack('>I', 0) + body + struct.pack('>I', 0)
    return head + struct.pack('>I', 3)

def tcp_conn(c):
    try:
        c.settimeout(10)
        while True:
            h = c.recv(4)
            if len(h) < 4:
                break
            n = struct.unpack('>I', h)[0] & 0x7fffffff
            req = b''
            while len(req) < n:
                d = c.recv(n - len(req))
                if not d:
                    return
                req += d
            r = reply(req)
            if r:
                c.sendall(struct.pack('>I', 0x80000000 | len(r)) + r)
    except Exception:
        pass
    finally:
        c.close()

def tcp_loop(s):
    while True:
        c, _ = s.accept()
        threading.Thread(target=tcp_conn, args=(c,), daemon=True).start()

def udp_loop(s):
    while True:
        d, a = s.recvfrom(1024)
        r = reply(d)
        if r:
            s.sendto(r, a)

t = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
t.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
t.bind((ip, 111)); t.listen(16)
u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
u.bind((ip, 111))
threading.Thread(target=tcp_loop, args=(t,), daemon=True).start()
threading.Thread(target=udp_loop, args=(u,), daemon=True).start()
while subprocess.call(['docker', 'inspect', cont], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) == 0:
    time.sleep(5)
