#!/bin/sh
# cifsdomjoincheck.sh <share address> <pool/volume> <domain> <requesting user>
# QSD5.352 r10 (QC 649): a domain CIFS share made with a wrong AD admin password (or an AD that cannot be reached, a
# wrong AD name, a clock skew) said 'Success' (NFS1004/NFS1007) and nothing else: the share container kept failing to
# join (adcli 'Preauthentication failed') and nobody was told.  VolumeCreateCIFSdom starts this in the background after
# the share container: it asks getdomvolstatus.sh (the status the volume list shows) every 5 s, 2 minutes at most, and
# a join error is logged as an error, one message code per reason (CIFS1041 wrong AD admin name or password, CIFS1042
# AD server not reachable, CIFS1043 wrong AD name, CIFS1044 clock skew).  The share is not removed: the user corrects
# the AD data or deletes it.  A join that is still loading after 2 minutes logs nothing.
# QSD5.352 r10b (validator N-1): the reason is in the message text, never an argument: logmsg2.sh splits the arguments
# on spaces (a reason with spaces was cut to its first word) and the log readers fill only ':' words.
ipaddr=$1
vol=$2
domname=$3
userreq=$4
TRIES=${CIFSDOMJOIN_TRIES:-24}
[ -f /TopStor/flavor.sh ] && . /TopStor/flavor.sh
GETST=${CIFSDOMJOIN_GETST:-/TopStor/getdomvolstatus.sh}
n=0
res=''
# QSD5.352 r10p (QC proof 10o F5, 586.2 / 587.1 / 588.3), container flavour: the share image (membersmb) runs realm
# discover, realm join (by the server address, so it joins the server's real realm whatever name was typed), sssd
# ('sssd is running'), then kinit / net ads join with the TYPED name.  The first poll that saw one final word decided:
# a wrong AD name (NOSUCHDOM) was polled between 'sssd is running' and the failed net ads join and passed as serviceok
# (no code), while a right join was polled after net ads join had printed NT_STATUS_NO_LOGON_SERVERS and was logged
# ADnameerror CIFS1043.  Now (container flavour): (1) the check waits until the entrypoint has ENDED (its last line
# 'Restarting Samba using supervisord', CIFSDOMJOIN_ENDTRIES polls of 5 s at most; a 'Preauthentication failed' or
# 'skew' is final at once); (2) the AD name is judged against what realm discover found: the typed name must be the
# realm, the DNS domain, the first label of either, or the NetBIOS workgroup of the domain; a name that matches none
# of them is ADnameerror (CIFS1043) even when the realm join worked; a matching name with only the
# NT_STATUS_NO_LOGON_SERVERS of the second join is serviceok (no code).  The physical flavour is unchanged.
remaking() {
 # a cifs.py or cifs.sh run for exactly this address is going on in this node: the share container of the address is
 # being made again (cifs.py -> cifs.sh: 'docker rm -f' then 'docker run', up to 5 tries).  Callers: VolumeActivateCIFSdom
 # (a second domain volume on the same address), VolumeCheck.py (repair of a dirty share), cifsremove.sh (restart after a
 # neighbour volume's delete).  In both command lines the address is followed by its subnet, so ' <ip> ' keeps .16 apart
 # from .164.  (r10q fix pass G-2b: was cifsmember.sh, whose only call is commented out: the wait never ran.)
 ps -eo args 2>/dev/null | grep -E '/TopStor/cifs\.(py|sh) ' | grep -v grep | grep -qF " $1 "
}
ctrof() {
 # the share container of exactly this address (its port map '<ip>:445->'; a plain grep of .16 also matched .165)
 docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -F "$1:445->" | awk '{print $1}' | head -1
}
# QSD5.352 r10q (QC proof 10p F5 remainder, 586.2 in r10n/r10o/r10p): the wrong-name share gave no code and no JOINLOG
# line at all.  zfs2 /root/cifsrun.log 2026-11-18 22:13:46: the NOSUCHDOM share container was started; 4 min later no
# container with '<ip>:445->' existed on either node (the harness SHR at 22:18:02): it had died and docker --rm removed it
# with its logs.  The check then saw only 'servicedown', ran out its polls and ended without a word (exit 0).  Now
# (container flavour): (1) the share's logs are copied to /root/cifsdomjoin.snap/<ip>.log at every poll, so a container
# that dies can still be judged from its last logs; (2) a container that vanished (CIFSDOMJOIN_GONETRIES polls) or was
# never seen (CIFSDOMJOIN_NEVERTRIES polls) while the volume still exists is judged at once: a wrong name in the last
# logs = ADnameerror (CIFS1043), otherwise ADservererror (CIFS1042, the share could not join); a deleted volume = no code;
# (3) a name that is definitely wrong (realm discovered, the domain's workgroup read and different) is final at once,
# without waiting for the entrypoint end (the code came after the 200 s window); (4) every run writes a start line and
# an end line (also 'no code') to /root/cifsdomjoin.trace.  /root/cifsdomjoin.log (JOINLOG) gets only coded lines.
# QSD5.352 r10q fix pass (validator G-2, G-2b): (1) a share container that vanished (or is not there yet) while cifs.py/cifs.sh re-create
# the share container of this address (a second domain volume on the same address: 'docker rm -f' then 'docker run', 1-2 min under
# load) is waited for up to CIFSDOMJOIN_REMAKETRIES polls (36 = 180 s) instead of being judged from the old container's
# logs after 15 s; when a container of the address is back, judging starts again from ITS logs (trace 'is back');
# with no re-create running the quick rule stays (CIFSDOMJOIN_GONETRIES 3 polls, so the 200 s window of a wrong name
# whose container died is kept); (2) the log copy is one file per check (<ip>.<pool_volume>.<pid>.log, copies older
# than one day are removed), two checks of one address no longer delete each other's copy; (3) a container still gone
# when the polls run out is judged as vanished (was: silent end).
SNAPDIR=${CIFSDOMJOIN_SNAPDIR:-/root/cifsdomjoin.snap}
TRACE=${CIFSDOMJOIN_TRACE:-/root/cifsdomjoin.trace}
JOINLOGF=${CIFSDOMJOIN_LOG:-/root/cifsdomjoin.log}
ZFSCMD=${CIFSDOMJOIN_ZFS:-/sbin/zfs}
trc() { echo "`date '+%F %T'` $vol $ipaddr $domname: $*" >> $TRACE; }
namejudge() {
 # $1 = container ('' when it is gone), $2 = file with its last logs; prints 'right', 'wrong' (workgroup read and
 # different: definite), 'wrongnowg' (none of the realm names, workgroup not readable) or 'unknown' (nothing discovered)
 logs=`cat "$2" 2>/dev/null`
 rn=`echo "$logs" | grep -i 'realm-name:' | tail -1 | awk -F': *' '{print $2}' | tr -d ' \r' | tr 'A-Z' 'a-z'`
 dn=`echo "$logs" | grep -i 'domain-name:' | tail -1 | awk -F': *' '{print $2}' | tr -d ' \r' | tr 'A-Z' 'a-z'`
 typed=`echo "$domname" | tr 'A-Z' 'a-z'`
 [ -z "$rn$dn" ] && { echo unknown; return; }
 for c in "$rn" "$dn" "${rn%%.*}" "${dn%%.*}"; do
  [ -n "$c" ] && [ "$c" = "$typed" ] && { echo right; return; }
 done
 wg=''
 [ -n "$1" ] && wg=`timeout 20 docker exec $1 net ads workgroup -S "${CIFSDOMJOIN_SERVER:-$dn}" 2>/dev/null | grep -i 'workgroup:' | awk -F': *' '{print $2}' | tr -d ' \r' | tr 'A-Z' 'a-z'`
 [ -n "$wg" ] && [ "$wg" = "$typed" ] && { echo right; return; }
 [ -n "$wg" ] && { echo wrong; return; }
 echo wrongnowg
}
if is_container 2>/dev/null; then
 ENDTRIES=${CIFSDOMJOIN_ENDTRIES:-90}
 GONETRIES=${CIFSDOMJOIN_GONETRIES:-3}
 NEVERTRIES=${CIFSDOMJOIN_NEVERTRIES:-12}
 EARLYTRIES=${CIFSDOMJOIN_EARLYTRIES:-3}
 REMAKETRIES=${CIFSDOMJOIN_REMAKETRIES:-36}
 mkdir -p $SNAPDIR 2>/dev/null; find $SNAPDIR -name '*.log' -mmin +1440 -delete 2>/dev/null
 snap=$SNAPDIR/$ipaddr.`echo $vol | tr '/' '_'`.$$.log; rm -f $snap $snap.new
 trc "check started (pid $$, log copy $snap)"
 ended=0; seen=0; gone=0; early=0; why=''; ctr=''; remk=0
 while [ $n -lt $ENDTRIES ]; do
  res=`$GETST $ipaddr CIFS 2>/dev/null | grep -o '_result[^_]*_result' | tail -1 | sed 's/_result//g'`
  case "$res" in adminpasserror|timeerror) ended=1; why=status; break ;; esac
  ctr=`ctrof $ipaddr`
  if [ -n "$ctr" ]; then
   if [ $gone -gt 0 ] && { [ $seen -eq 1 ] || [ $remk -eq 1 ]; }; then
    # the address has a share container again (re-created): judge from its own logs, not the old container's
    trc "share container of the address is back after $gone polls ($ctr): judging its logs"
    rm -f $snap; early=0
   fi
   seen=1; gone=0; remk=0
   docker logs $ctr > $snap.new 2>&1; [ -s $snap.new ] && mv -f $snap.new $snap
   # a server that was not even discovered is final at once (586.1 unreachable DC); with a discovered one it waits
   if [ "$res" = ADservererror ] && ! grep -q 'Successfully discovered' $snap 2>/dev/null; then ended=1; why=nodiscovery; break; fi
   if grep -q 'Restarting Samba using supervisord' $snap 2>/dev/null; then ended=1; why=entrypoint; break; fi
   if [ $early -lt $EARLYTRIES ] && grep -qi 'realm-name:' $snap 2>/dev/null; then
    early=$((early+1))
    nj=`namejudge $ctr $snap`
    [ "$nj" = wrong ] && { ended=1; why=earlyname; res=ADnameerror; break; }
   fi
  else
   gone=$((gone+1))
   if [ $gone -lt $REMAKETRIES ] && remaking $ipaddr; then
    [ $remk -eq 0 ] && trc "share container gone while cifs.py/cifs.sh makes it again: waiting up to $REMAKETRIES polls"
    remk=1
   else
    [ $seen -eq 1 ] && [ $gone -ge $GONETRIES ] && { why=vanished; break; }
    [ $seen -eq 0 ] && [ $gone -ge $NEVERTRIES ] && { why=neverseen; break; }
   fi
  fi
  sleep 5
  n=$((n+1))
 done
 [ -z "$why" ] && [ $gone -gt 0 ] && { [ $seen -eq 1 ] && why=vanished || why=neverseen; }
 [ -z "$why" ] && why=polls
 if [ "$why" = vanished ] || [ "$why" = neverseen ]; then
  if ! timeout 20 $ZFSCMD list -H -o name $vol >/dev/null 2>&1; then trc "share container $why and the volume is gone (deleted): no code"; exit 0; fi
  nj=`namejudge '' $snap`
  case "$nj" in wrong*) res=ADnameerror ;; *) res=ADservererror ;; esac
  trc "share container $why (last status '$res', logs kept `grep -c . $snap 2>/dev/null || echo 0` lines), name $nj: judged $res"
 elif [ "$why" = earlyname ]; then
  trc "name $nj (realm discovered, workgroup differs) before the entrypoint end: judged $res"
 elif [ -n "$ctr" ]; then
  case "$res" in
   serviceok|ADnameerror)
    nj=`namejudge $ctr $snap`
    trc "status $res, entrypoint ended $ended ($why), name $nj"
    # r10p1 (validator G-1): a right name is serviceok only when the realm join itself worked; the entrypoint goes on
    # after a failed 'realm join' and its second join prints NO_LOGON_SERVERS, so without this check a share that
    # never joined got no code.  A failed realm join with a right name is ADservererror (CIFS1042).
    case "$nj" in
     wrong*) res=ADnameerror ;;
     right) if grep -q "Couldn't join realm" $snap 2>/dev/null; then res=ADservererror; else res=serviceok; fi ;;
    esac
    trc "judged $res (realm join `grep -c 'Successfully enrolled' $snap 2>/dev/null` enrolled)" ;;
  esac
 fi
 case "$res" in adminpasserror|ADservererror|ADnameerror|timeerror) ;; *) trc "end ($why): status '$res', no code"; exit 0 ;; esac
else
while [ $n -lt $TRIES ]; do
 res=`/TopStor/getdomvolstatus.sh $ipaddr CIFS 2>/dev/null | grep -o '_result[^_]*_result' | tail -1 | sed 's/_result//g'`
 case "$res" in serviceok|adminpasserror|ADservererror|ADnameerror|timeerror) break ;; esac
 sleep 5
 n=$((n+1))
done
fi
case "$res" in
 adminpasserror) code=CIFS1041 ;;
 ADservererror) code=CIFS1042 ;;
 ADnameerror) code=CIFS1043 ;;
 timeerror) code=CIFS1044 ;;
 *) exit 0 ;;
esac
echo "`date '+%F %T'` $vol $ipaddr $domname: $res $code" >> ${JOINLOGF:-/root/cifsdomjoin.log}
docker exec etcdclient /TopStor/logmsg.py $code error $userreq $vol $domname
exit 1
