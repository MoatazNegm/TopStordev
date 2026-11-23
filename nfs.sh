#!/bin/sh
export ETCDCTL_API=3
ipaddr=`echo $@ | awk '{print $1}'`
ipsubnet=`echo $@ | awk '{print $2}'`
# QSD5.337 (test 646): share address live via shareaddr.sh, no "nmcli conn up cmynode" (bond0 re-activation drops every address)
/TopStor/shareaddr.sh add $ipaddr $ipsubnet
echo '# init' > /etc/exports
cat /TopStordata/exportip.* > /etc/exports
exportfs -r
