#!/bin/sh
egrep 'etcdget|etcddel|etcdput'  /pace/* | egrep -v 'erase|Snapshot|SnapShot|Zpoolclrrun|Volume|Zpool|UpdateName|Unix|toonline|target|repli|Partner|Release|receivekeys|pumpkey|prot|riv|poolall|PartnerAdd|nfs|missing|log|Manual|Join|iscsi|Hostsconfig|Hostconfig|hostlost|Hostget|getallraids|fapi|fixpool|DG|Evacuate|electspare|docker_setup|sync|cifs.sh|broadcast'
#grep 'hostname'
#grep 'broadcast' | grep -v '#' 
