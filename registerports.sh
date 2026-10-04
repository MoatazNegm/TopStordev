#!/bin/bash

# Usage: ./registerports.sh hostip
# This script registers network ports into etcd under ports/<hostname>/p1, p2, etc.

if [ $# -ne 1 ]; then
    echo "Usage: $0 <hostname>"
    exit 1
fi

hostip="$1"
myhost=$(hostname)
stamp=$(date +%s%N)

# Get the list of ports from listports.sh
ports=$(/TopStor/listports.sh)

if [ -z "$ports" ]; then
    echo "No ports found to register"
    exit 0
fi

# Convert newlines to forward slashes
ports_value=$(echo "$ports" | tr '\n' '/' | sed 's/\/$//')

# Register all ports in one key
key="ports/${myhost}"
echo "Registering: $key -> $ports_value"
/TopStor/etcdput.py $hostip $key $ports_value
/TopStor/etcdput.py $hostip sync/ports/${myhost}_${stamp}/request syncports_${stamp}
/TopStor/etcdput.py $hostip sync/ports/${myhost}_${stamp}/request/${myhost} syncports_${stamp}

if [ $? -eq 0 ]; then
    echo "Successfully registered ports for $myhost"
else
    echo "Failed to register ports for $myhost"
fi

