#!/bin/sh
export ETCDCTL_API=3
cd /TopStor/
prot=`echo $@ | awk '{print $1}'`

if [[ $prot == 'nfs' ]];
then
 head -n 2 /pdhcp*/exports.* | grep NFS | grep SUMMARY |  awk '{print $4}' 2>/dev/null
 exit
fi

if [[ $prot == 'cifs' ]];
then
 head -n 2 /pdhcp*/smb.* | grep CIFS | grep SUMMARY |  awk '{print $4}' 2>/dev/null
 exit
fi
if [[ $prot == 'home' ]];
then
 head -n 2 /pdhcp*/smb.* | grep HOME | grep SUMMARY |  awk '{print $4}' 2>/dev/null
 exit
fi
if [[ $prot == 'iscsi' ]];
then
 head -n 2 /pdhcp*/iscsi.* | grep ISCSI | grep SUMMARY | awk -F'ISCSI ' '{print $2}' 2>/dev/null
 exit
fi
