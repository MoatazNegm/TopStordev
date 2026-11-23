#!/usr/bin/python3
import sys, os, subprocess, datetime, fcntl, shutil
from logqueue import queuethis, initqueue
from etcdgetpy import etcdget as get
from sendhost import sendhost
from time import sleep


_cifslock = None


def domstatus(ipaddr, vtype, status):
    # QSD5.339 (test 649 QX-050): the result of a DOMAIN share container for VolumeCreateCIFSdom (joined / nojoin / nocontainer /
    # notmounted / ipinuse); a create that is not "joined" logs the failure and leaves nothing behind
    if '_' not in vtype:
        return
    with open('/TopStordata/cifsdomjoin.'+ipaddr,'w') as f:
        f.write(status+'\n')

def hasvol(vols, name):
    return any(isinstance(x, tuple) and str(x[0]).split('/')[-1] == name for x in vols)

def create(leader, leaderip, myhost, myhostip, etcdip, pool, name, ipaddr, ipsubnet, vtype,*args):
    # QSD5.327: after a take over the activation script and VolumeCheck both start cifs.py for the same address. Each run
    # starts with rm -rf of /TopStordata/smb.<ip> and tempsmb.<ip>, so one run deleted the config of the other and docker
    # bind-mounted the missing file as an empty DIRECTORY: the share container ran without any share (BAD_NETWORK_NAME)
    # and nobody repaired it. One run per address at a time; the lock is released when the process ends.
    global _cifslock
    _cifslock = open('/TopStordata/cifs.'+ipaddr+'.lock','w')
    fcntl.flock(_cifslock, fcntl.LOCK_EX)
    volsip = get(etcdip,'volume','/'+ipaddr+'/')
    volsip = [ x for x in volsip if 'active' in str(x) ]
    if etcdip != leaderip and not hasvol(volsip, name):
        # QSD5.339 (test 649 QX-050 step 1): on a follower the local etcd may not have the new volume yet (the record is written to
        # the leader's etcd, the sync comes later): read the leader's etcd, as the node that owns the record does
        print('volume', name, 'not in the local etcd', etcdip, ': reading the leader etcd', leaderip)
        etcdip = leaderip
        volsip = get(etcdip,'volume','/'+ipaddr+'/')
        volsip = [ x for x in volsip if 'active' in str(x) ]
    nodesip = get(etcdip, 'Active','/'+ipaddr+'/') 
    notsametype = [ x for x in volsip if vtype not in str(x) ]
    if (len(nodesip) > 0 and 'Active' in str(nodesip))or len(notsametype) > 0:
        print('ipaddr',ipaddr)
        print('nodesip',len(nodesip), nodesip)
        print('nodtsametype',len(notsametype), notsametype)
        print(' the ip address is in use ')
        domstatus(ipaddr, vtype, 'ipinuse')
        return 5
    resname = vtype+'-'+ipaddr
    # QSD5.352 r9b (validator r9 V1): the active records of this address and type that this run starts (stale records
    # included: they are skipped below, but they do not change while the share starts)
    startkeys = sorted(str(x[0]) for x in volsip if x not in notsametype)
    cmdline='rm -rf /TopStordata/tempsmb.'+ipaddr
    subprocess.run(cmdline.split(),stdout=subprocess.PIPE)  
    # test 16 step 9: smb.<ip> is no longer removed here and copied back later. In that gap a parallel start's
    # `docker run -v /TopStordata/smb.<ip>:/etc/smb.conf` found no source and docker created a DIRECTORY there: the share
    # section never reached the container (domain share joined but BAD_NETWORK_NAME). It is replaced atomically below;
    # a directory left by such a run is removed.
    if os.path.isdir('/TopStordata/smb.'+ipaddr):
        shutil.rmtree('/TopStordata/smb.'+ipaddr, ignore_errors=True)
    mounts =''
    # right after a take over this runs while the pool is still being imported: the volume's dataset is not mounted and
    # /<pool>/smb.<volume> is not readable yet. Reading it then (the error was skipped) gave an empty smb config and a
    # share container without any share, and nothing retried. Wait for the dataset; if it never comes, start nothing:
    # the volume stays dirty and the next volume check starts it again.
    staleskip = []
    for vol in volsip:
        if vol in notsametype:
           continue
        leftvol = vol[0].split('/')[4]
        # QSD5.329: a stale volume record (the user and its dataset are gone, the etcd record stayed) waited 180 s per run
        # and the share of the address was never started. No dataset at all = nothing to wait for and nothing to share.
        exist = subprocess.run(['zfs','list','-H','-o','name',pool+'/'+leftvol],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        poolok = subprocess.run(['zfs','list','-H','-o','name',pool],stdout=subprocess.PIPE,stderr=subprocess.PIPE).returncode == 0
        if exist.returncode != 0 and poolok:
            print('stale volume record, dataset missing, skipped', pool, leftvol)
            staleskip.append(vol)
            continue
        for attempt in range(90):
            mounted = subprocess.run(['zfs','list','-H','-o','mounted',pool+'/'+leftvol],stdout=subprocess.PIPE,stderr=subprocess.PIPE).stdout.decode().strip()
            if mounted == 'yes' and os.path.exists('/'+pool+'/smb.'+leftvol):
                break
            sleep(2)
        else:
            print('pool volume not mounted yet, not starting the share', pool, leftvol)
            domstatus(ipaddr, vtype, 'notmounted')
            return 6
    volsip = [ x for x in volsip if x not in staleskip ]
    for vol in volsip:
        if vol in notsametype:
           continue
        leftvol = vol[0].split('/')[4]
        mounts += '-v/'+pool+'/'+leftvol+':/'+pool+'/'+leftvol+':rw'
        with open('/TopStordata/tempsmb.'+ipaddr,'a') as fip:
            try:
                with open('/'+pool+'/smb.'+leftvol, 'r') as fvol:
                    fip.write(fvol.read())
            except:
               continue 
    if not os.path.exists('/TopStordata/tempsmb.'+ipaddr):
        open('/TopStordata/tempsmb.'+ipaddr,'a').close()
    shutil.copyfile('/TopStordata/tempsmb.'+ipaddr, '/TopStordata/smb.'+ipaddr+'.new')
    if os.path.isdir('/TopStordata/smb.'+ipaddr):
        shutil.rmtree('/TopStordata/smb.'+ipaddr, ignore_errors=True)
    os.replace('/TopStordata/smb.'+ipaddr+'.new', '/TopStordata/smb.'+ipaddr)
    # merge M+A (M): an empty share config starts no container
    if not os.path.isfile('/TopStordata/smb.'+ipaddr) or os.path.getsize('/TopStordata/smb.'+ipaddr) == 0:
        print('no share config for', ipaddr, 'volumes found:', len(volsip), 'not starting an empty share container')
        domstatus(ipaddr, vtype, 'nocontainer')   # merge M+A: A's result codes
        return 4
    if '_' not in vtype:
        cmdline = 'cp /TopStor/VolumeCIFSupdate.sh /etc/'
        subprocess.run(cmdline.split(),stdout=subprocess.PIPE)  
    print('hihihihi')
    print('cmd: '+'/TopStor/cifs.sh '+resname+' '+mounts+' '+ipaddr+' '+ipsubnet+' '+vtype+' '+" ".join(args))
    print('end of cmd')
    cmdline = '/TopStor/cifs.sh '+resname+' '+mounts+' '+ipaddr+' '+ipsubnet+' '+vtype+' '+" ".join(args)
    # the share container can die within seconds of its start (docker --rm then removes it and its logs): after the second
    # take over of a test the container was created, found "not running" 2 s later and nobody started it again -- the
    # password loop below then ran for minutes against a container that did not exist, and VolumeCheck (which waits for
    # this script) could not repair anything.  Start it again until it stays up; keep the output of every try.
    running = False
    for attempt in range(5):
        if attempt > 0:
            # r9b (validator r9 V1): the container is gone: removed by a delete or change of this address (cifsremove.sh,
            # volbusyfree.sh, VolumeChangeHOME; they do not take this address's lock) or it died.  The mount list above was
            # read at the start: a home deleted in between came back in a new container (docker made an empty directory
            # /<pool>/<home> after the destroy, the address went up again).  Started again only while the address still
            # has the volumes this run read; otherwise the caller / the next VolumeCheck pass decides.  An unreadable
            # registry ('_1') also stops here (VolumeCheck starts the share later).
            nowv = [ x for x in get(etcdip,'volume','/'+ipaddr+'/') if 'active' in str(x) and vtype in str(x) ]
            if sorted(str(x[0]) for x in nowv) != startkeys:
                print('the volumes of', ipaddr, 'changed while the share was starting: left to VolumeCheck')
                with open('/root/cifsrun.log','a') as flog:
                    flog.write(str(datetime.datetime.now())+' '+resname+' stopped: the volumes of '+ipaddr+' changed while the share was starting\n')
                return
        res = subprocess.run(cmdline.split(),stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        with open('/root/cifsrun.log','a') as flog:
            flog.write(str(datetime.datetime.now())+' '+resname+' try '+str(attempt)+'\n'+res.stdout.decode()[-1500:]+'\n')
        sleep(8)
        up = subprocess.run(['docker','ps','-q','-f','name=^'+resname+'$'],stdout=subprocess.PIPE).stdout.decode().strip()
        if up:
            running = True
            break
    if not running:
        print('share container did not stay up after 5 tries, see /root/cifsrun.log', resname)
        domstatus(ipaddr, vtype, 'nocontainer')
        return 4
    if '_' in vtype:
        # QSD5.339 (test 649 QX-050 steps 1, 4): the domain member image (membersmb) joins the domain in its entrypoint and then
        # runs supervisord whatever the join gave: a wrong administrator password left a running container that serves nobody and
        # the create said "success". Wait for "net ads testjoin" (up to ~3 min); once the entrypoint is done (PID 1 is
        # supervisord) and the test still fails a few times, the join failed.
        joined = False
        failed = 0
        tj = None
        for attempt in range(90):
            tj = subprocess.run(['docker','exec',resname,'net','ads','testjoin'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
            if tj.returncode == 0:
                joined = True
                break
            if not subprocess.run(['docker','ps','-q','-f','name=^'+resname+'$'],stdout=subprocess.PIPE).stdout.decode().strip():
                break
            pid1 = subprocess.run(['docker','exec',resname,'cat','/proc/1/cmdline'],stdout=subprocess.PIPE,stderr=subprocess.PIPE).stdout
            if b'supervisord' in pid1 and b'docker-entrypoint' not in pid1:   # the entrypoint runs as "bash /docker-entrypoint.sh supervisord ..." until its exec
                failed += 1
                if failed >= 5:
                    break
            sleep(2)
        with open('/root/cifsrun.log','a') as flog:
            flog.write(str(datetime.datetime.now())+' '+resname+' testjoin joined='+str(joined)+' tries='+str(attempt+1)+'\n'+(tj.stdout.decode()[-500:] if tj else '')+'\n')
        domstatus(ipaddr, vtype, 'joined' if joined else 'nojoin')
        if not joined:
            print('the share container did not join the domain', resname)
            return 3
    if '_' not in vtype:
        # the script that sets a user's samba password inside the share container; UnixAddUser_sync copies it, but the
        # node that created the users (the leader runs UnixAddUser) never ran that, so a share created later found no file
        subprocess.run(['cp','-f','/TopStor/smbuserfix.sh','/etc/smbuserfix.sh'],stdout=subprocess.PIPE)
        users=get(etcdip,'usershash','--prefix')
        # QSD5.350: skip admin by its exact key ('admin' not in x[0] was a substring test: it-admin, admin-ops ... got no
        # samba password in a share container started later, so after a password change plus a take-over the OLD CIFS
        # password still worked there); a '_1' answer (etcd not reachable) is not a user
        users=[x for x in users if isinstance(x, tuple) and len(x) == 2 and x[0].startswith('usershash/') and x[0] != 'usershash/admin' ]
        for user in users:
            username = user[0].split('/')[1]
            cmdline = '/TopStor/decthis.sh '+username+' '+user[1]
            passwd = subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode().split('_result')[1]
            # the share container is started in the background: its samba database may not answer yet, so the password is
            # set again until the user is in it (up to ~3 min; two shares created together take longer)
            for attempt in range(75):
                if not subprocess.run(['docker','ps','-q','-f','name=^'+resname+'$'],stdout=subprocess.PIPE).stdout.decode().strip():
                    print('share container is gone, password of', username, 'not set')
                    break
                cmdline = 'docker exec '+resname+' /hostetc/smbuserfix.sh x '+username+' '+passwd
                subprocess.run(cmdline.split(),stdout=subprocess.PIPE,stderr=subprocess.PIPE)
                check = subprocess.run(['docker','exec',resname,'pdbedit','-L','-u',username],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
                if check.returncode == 0 and username.encode() in check.stdout:
                    break
                sleep(2)
            
    print(mounts)
    return
    #if len(checkipaddr1) != 0 or len :

 

def built(resname, ipaddr, name, vtype):
    """the container of the address runs (and for a domain share is joined) with this share in its smb config"""
    if not subprocess.run(['docker','ps','-q','-f','name=^'+resname+'$'],stdout=subprocess.PIPE).stdout.decode().strip():
        return False
    try:
        with open('/TopStordata/smb.'+ipaddr) as f:
            if '['+name+']' not in f.read():
                return False
    except (OSError, IsADirectoryError):
        return False
    if '_' in vtype:
        return subprocess.run(['docker','exec',resname,'net','ads','testjoin'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT).returncode == 0
    return True

def lockedcreate(leader, leaderip, myhost, myhostip, etcdip, pool, name, ipaddr, ipsubnet, vtype, *args):
    """test 16 step 9: one cifs.py per share address at a time (VolumeActivateCIFSdom and the VolumeCheck repair started two for
    the same address within 4 s; see the smb.<ip> note in create). The lock is /tmp/shareaddr.<ip>.lock, as for NFS; a caller that
    holds it names the address in SHAREADDR_LOCK. A run that had to wait finds the container already built with this share and
    leaves it alone."""
    if ipaddr in os.environ.get('SHAREADDR_LOCK','').split():
        return create(leader, leaderip, myhost, myhostip, etcdip, pool, name, ipaddr, ipsubnet, vtype, *args)
    try:
        lockf = open('/tmp/shareaddr.'+ipaddr+'.lock','w')
    except OSError:
        return create(leader, leaderip, myhost, myhostip, etcdip, pool, name, ipaddr, ipsubnet, vtype, *args)
    try:
        try:
            fcntl.flock(lockf, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            print('address', ipaddr, 'is being built by another job: waiting')
            for attempt in range(150):
                sleep(2)
                try:
                    fcntl.flock(lockf, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except OSError:
                    continue
            else:
                print('address lock not free after 300 s, building anyway', ipaddr)
            if built(vtype+'-'+ipaddr, ipaddr, name, vtype):
                print('container', vtype+'-'+ipaddr, 'already built with', name, 'by the other job')
                domstatus(ipaddr, vtype, 'joined')
                return
        return create(leader, leaderip, myhost, myhostip, etcdip, pool, name, ipaddr, ipsubnet, vtype, *args)
    finally:
        lockf.close()

if __name__=='__main__':
 leader = sys.argv[1]
 leaderip = sys.argv[2]
 myhost = sys.argv[3]
 myhostip = sys.argv[4]
 etcdip = sys.argv[5]
 pool = sys.argv[6]
 name = sys.argv[7]
 ipaddr = sys.argv[8]
 ipsubnet = sys.argv[9]
 vtype = sys.argv[10]
 initqueue(leaderip, myhost)
 with open('/root/cifspytmp','w') as f:
  f.write(str(sys.argv))
 res = lockedcreate(leader, leaderip, myhost, myhostip, etcdip, pool, name, ipaddr, ipsubnet, vtype,*sys.argv[11:])
 if res and '_' in vtype:
  # a domain share that is not up and joined (the workgroup and home exit codes are unchanged)
  sys.exit(res)
