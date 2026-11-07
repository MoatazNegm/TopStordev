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
n=0
res=''
while [ $n -lt $TRIES ]; do
 res=`/TopStor/getdomvolstatus.sh $ipaddr CIFS 2>/dev/null | grep -o '_result[^_]*_result' | tail -1 | sed 's/_result//g'`
 case "$res" in serviceok|adminpasserror|ADservererror|ADnameerror|timeerror) break ;; esac
 sleep 5
 n=$((n+1))
done
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
