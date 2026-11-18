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
ctrof() {
 # the share container of exactly this address (its port map '<ip>:445->'; a plain grep of .16 also matched .165)
 docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -F "$1:445->" | awk '{print $1}' | head -1
}
namejudge() {
 # $1 = container: prints 'right', 'wrong' or 'unknown' for the typed domain name $domname
 logs=`docker logs $1 2>&1`
 rn=`echo "$logs" | grep -i 'realm-name:' | tail -1 | awk -F': *' '{print $2}' | tr -d ' \r' | tr 'A-Z' 'a-z'`
 dn=`echo "$logs" | grep -i 'domain-name:' | tail -1 | awk -F': *' '{print $2}' | tr -d ' \r' | tr 'A-Z' 'a-z'`
 typed=`echo "$domname" | tr 'A-Z' 'a-z'`
 [ -z "$rn$dn" ] && { echo unknown; return; }
 for c in "$rn" "$dn" "${rn%%.*}" "${dn%%.*}"; do
  [ -n "$c" ] && [ "$c" = "$typed" ] && { echo right; return; }
 done
 wg=`timeout 20 docker exec $1 net ads workgroup -S "${CIFSDOMJOIN_SERVER:-$dn}" 2>/dev/null | grep -i 'workgroup:' | awk -F': *' '{print $2}' | tr -d ' \r' | tr 'A-Z' 'a-z'`
 [ -n "$wg" ] && [ "$wg" = "$typed" ] && { echo right; return; }
 echo wrong
}
if is_container 2>/dev/null; then
 ENDTRIES=${CIFSDOMJOIN_ENDTRIES:-90}
 ended=0
 while [ $n -lt $ENDTRIES ]; do
  res=`$GETST $ipaddr CIFS 2>/dev/null | grep -o '_result[^_]*_result' | tail -1 | sed 's/_result//g'`
  case "$res" in adminpasserror|timeerror) ended=1; break ;; esac
  ctr=`ctrof $ipaddr`
  # a server that was not even discovered is final at once (586.1 unreachable DC); with a discovered one it waits
  if [ "$res" = ADservererror ] && [ -n "$ctr" ] && ! docker logs $ctr 2>&1 | grep -q 'Successfully discovered'; then ended=1; break; fi
  if [ -n "$ctr" ] && docker logs $ctr 2>&1 | grep -q 'Restarting Samba using supervisord'; then ended=1; break; fi
  sleep 5
  n=$((n+1))
 done
 if [ -n "$ctr" ]; then
  case "$res" in
   serviceok|ADnameerror)
    nj=`namejudge $ctr`
    echo "`date '+%F %T'` $vol $ipaddr $domname: status $res, entrypoint ended $ended, name $nj" >> /root/cifsdomjoin.trace
    # r10p1 (validator G-1): a right name is serviceok only when the realm join itself worked; the entrypoint goes on
    # after a failed 'realm join' and its second join prints NO_LOGON_SERVERS, so without this check a share that
    # never joined got no code.  A failed realm join with a right name is ADservererror (CIFS1042).
    if [ "$nj" = wrong ]; then res=ADnameerror
    elif [ "$nj" = right ]; then
     if docker logs $ctr 2>&1 | grep -q "Couldn't join realm"; then res=ADservererror; else res=serviceok; fi
    fi
    echo "`date '+%F %T'` $vol $ipaddr $domname: judged $res (realm join `docker logs $ctr 2>&1 | grep -c 'Successfully enrolled'` enrolled)" >> /root/cifsdomjoin.trace ;;
  esac
 fi
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
echo "`date '+%F %T'` $vol $ipaddr $domname: $res $code" >> /root/cifsdomjoin.log
docker exec etcdclient /TopStor/logmsg.py $code error $userreq $vol $domname
exit 1
