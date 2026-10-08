#!/bin/sh
# getlatestsnap.sh <volume> [<pool/volume of the receiver>]   latest snapshot of a volume on THIS cluster (run on the
# receiver by replicatenow.py).  With the second argument only the snapshots of that dataset count: grepping the bare
# volume name also matched the SENDER's snapshots of the same volume name whenever both clusters see the same ZFS (the
# container flavour: one kernel for all node containers), so the "latest snapshot on the receiver" was the sender's own
# snapshot and the stream was an incremental from a snapshot to itself.
name=`echo $@ | awk '{print $1}'`
poolvol=`echo $@ | awk '{print $2}'`
if [ -n "$poolvol" ]
then
	snaps=`zfs list -t snapshot -H -o name | grep "^${poolvol}@"`
else
	snaps=`zfs list -t snapshot | grep $name | awk '{print $1}'`
fi
latestsnap=`echo "$snaps" | awk -F'.' '{print $NF}' | sort | tail -1`
latestsnapn=`echo "$snaps" | grep -w "$latestsnap" | head -1`
echo 'hi'$latestsnapn | grep pdhcp
if [ $? -eq 0 ];
then

	echo result_${latestsnap}result_${latestsnapn}result_
else
	echo result_nooldresult_
fi
