#!/bin/sh
export ETCDCTL_API=3
cd /TopStor/
name=`echo $@ | awk '{print $1}'`
echo dockername=$name > /root/tmpundoc
dockname=` docker ps | grep -w $name | awk '{print $NF}'`
docker rm -f $dockname
