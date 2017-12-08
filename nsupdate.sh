#!/bin/sh
enp0s0=`ip a | grep enp[0-9]s[0-9] | head -1 | awk -F': ' '{print $2}'`
requireddomain=`cat /etc/resolv.conf | grep search | awk -F'search ' '{print $2}' | awk '{print $1}'`
 host=`hostname -s`
 new_ip_address=`ip a | grep "$enp0s0" | grep inet | awk -F'inet' '{print $2}' | awk '{print $1}' | head -1 | awk -F'/' '{print $1}'`
 nsupdatecmds=/var/tmp/nsupdatecmds
 echo "update delete $host.$requireddomain a " > $nsupdatecmds
 echo "update add $host.$requireddomain 3600 a $new_ip_address" >> $nsupdatecmds
 echo "send" >> $nsupdatecmds
 nsupdate -d $nsupdatecmds
#done
