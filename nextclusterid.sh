#!/bin/sh
# nextclusterid.sh <etcd ip>   (test 678 step 2)
# The next uid/gid that is free on this node AND in the cluster: useradd picked the id from the local /etc/passwd and
# /etc/group only, so the leader gave a new group the gid of a group the cluster already had (q003g1 1001, missing from the
# leader's /etc/group); the follower's copy of the new group then failed (Unlin1120) and its members lacked it.
etcd=$1
{
 awk -F: '$3>=1000 && $3<60000 {print $3}' /etc/passwd /etc/group
 /TopStor/etcdget.py $etcd usersinfo --prefix 2>/dev/null | sed -n "s/.*', '\([0-9][0-9]*\):\([0-9][0-9]*\):.*/\1\n\2/p"
 /TopStor/etcdget.py $etcd usersigroup --prefix 2>/dev/null | sed -n "s/.*', '\([0-9][0-9]*\):\([0-9][0-9]*\):.*/\1\n\2/p"
} | awk '$1>=1000 && $1<60000 {if ($1>m) m=$1} END {print (m<1000 ? 1001 : m+1)}'
