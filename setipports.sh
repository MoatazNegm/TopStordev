#!/usr/bin/sh
echo $@ > /root/ipports
clusterip=`echo $@ | awk '{print $1}'`
reserved=${clusterip}'/10.11.11.254/10.11.11.253/10.11.11.251/10.11.11.252';
leader=` echo $@ | awk '{print $2}'`;
myhost=` echo $@ | awk '{print $3}'`;
pstatus=` echo $@ | awk '{print $4}'`;
pports=$(ip a | awk -F: '/^[0-9]+: / {print $2}' | tr -d ' ')
vols=`/TopStor/etcdget.py $clusterip vol --prefix`
olderports=`/TopStor/etcdget.py $clusterip etherports $myhost`
dirtyports=0
# Loop through each interface and extract IP addresses
for port in $pports; do
    if [[ "$pstatus" == "sync" && "$olderports" =~ "$port" ]];
    then
	continue
    fi
    case $port in
            lo|docker*|veth*|br-*|virbr*|vnet*|tun*|tap*|bond*|team*|vlan*)
			continue;;
	    *)
		    # Extract IP addresses for the current interface
		    ip_addresses=$(ip a show "$port" 2>/dev/null | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+')
		    concatenated_ips=''
		    for ip_addr in $ip_addresses; do
			if [[ "$vols" =~ "$ip_addr" || "$reserved" =~ "$ip_addr" ]];
			then
				continue
			else
				concatenated_ips=${concatenated_ips}$ip_addr'/'
			fi	
		    done
		    # Proceed only if the interface has IP addresses
		    if [ -n "$concatenated_ips" ]; then
			    /TopStor/etcdput.py $clusterip "etherports/$myhost/$port" "${concatenated_ips%?}"
		    	    dirtyports=1
		    fi
    esac
done
if [ $dirtyports -eq 1 ];
then
	stamp=`date +%s%N`
	/pace/etcddel.py $clusterip sync/etherports --prefix 
	/pace/etcdput.py $clusterip sync/etherports/${myhost}/request etherports_$stamp.
	/pace/etcdput.py $clusterip sync/etherports/${myhost}/request/$leader etherports_$stamp.
fi


