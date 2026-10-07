#!/bin/sh
etcd=`echo $@ | awk '{print $1}'`
myhost=`echo $@ | awk '{print $2}'`
cores=`lscpu  | grep 'CPU(s):' | grep -v NUMA | awk '{print $2}'`
loadavg=`uptime | awk -F'average:' '{print $2}'  | awk -F',' '{print $1}' `
echo $cores $loadavg
