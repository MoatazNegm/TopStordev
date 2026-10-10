#!/bin/sh
export ETCDCTL_API=3
cd /TopStor/
prot=`echo $@ | awk '{print $1}'`
# container flavour: all node containers share one kernel, so another cluster's pool can be mounted in this node too.
# Only the pools this node owns (zfs property topstor:owner, pace/cpoolowner.sh) are listed; physical servers keep /pdhcp*.
PD='/pdhcp*'
[ -f /TopStor/flavor.sh ] && . /TopStor/flavor.sh
if is_container 2>/dev/null && [ -x /pace/cpoolowner.sh ]; then
	PD=`for p in \`/pace/cpoolowner.sh mine $(hostname) 2>/dev/null\`; do echo /$p; done | tr '\n' ' '`
	[ -n "$PD" ] || PD=/nopool
fi
files() { for d in $PD; do echo $d/$1; done; }

if [[ $prot == 'nfs' ]];
then
 head -n 2 `files 'exports.*'` 2>/dev/null | grep NFS | grep SUMMARY |  awk '{print $4}' 2>/dev/null
 exit
fi

if [[ $prot == 'cifs' ]];
then
 head -n 2 `files 'smb.*'` 2>/dev//null | grep CIFS | grep SUMMARY |  awk '{print $4}' 2>/dev/null
 exit
fi
if [[ $prot == 'home' ]];
then
 head -n 2 `files 'smb.*'` 2>/dev/null | grep HOME | grep SUMMARY |  awk '{print $4}' 2>/dev/null
 exit
fi
if [[ $prot == 'iscsi' ]];
then
 head -n 2 `files 'iscsi.*'` 2>/dev/null | grep ISCSI | grep SUMMARY | awk -F'ISCSI ' '{print $2}' 2>/dev/null
 exit
fi
