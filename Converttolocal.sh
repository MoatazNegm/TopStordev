#!/bin/sh
export ETCDCTL_API=3
cd /TopStor/
myip=`echo $@ | awk '{print $1}'`
echo starting etcd as local >>/root/tmp2
./etccluster.py 'local' $myip 2>/dev/null
chmod +r /etc/etcd/etcd.conf.yml 2>/dev/null
systemctl daemon-reload 2>/dev/null
systemctl stop etcd 2>/dev/null
systemctl start etcd 2>/dev/null
