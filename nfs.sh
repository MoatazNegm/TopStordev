#!/bin/sh
export ETCDCTL_API=3
ipaddr=`echo $@ | awk '{print $1}'`
ipsubnet=`echo $@ | awk '{print $2}'`
/TopStor/cmynodeaddr.sh add $ipaddr $ipsubnet    # QSD5.352 (QC 698): locked, checked, retried
echo '# init' > /etc/exports
cat /TopStordata/exportip.* > /etc/exports
exportfs -r
