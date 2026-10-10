#!/bin/bash
set -u   # Treat unset variables as an error

echo "========== Starting Combined Script =========="
echo "Arguments received: $@"

# Get the current directory
leaderip=$(echo $@ | awk '{print $1}')
myhost=$(hostname)
echo "[INFO] leaderip=$leaderip"
echo "[INFO] myhost=$myhost"

leader=$(/TopStor/etcdget.py $leaderip leader)
myhostip=$(/TopStor/etcdget.py $leaderip ready/$myhost)
echo "[INFO] leader=$leader"
echo "[INFO] myhostip=$myhostip"

echo "[CHECK] Checking if current host is the leader..."
echo $leader | grep $myhost >/dev/null
if [ $? -eq 0 ]; then
    echo "[INFO] This host ($myhost) is the leader. Using etcdip=$leaderip"
    etcdip=$leaderip
else
    echo "[INFO] This host is NOT the leader. Using etcdip=$myhostip"
    etcdip=$myhostip
fi

current_dir='/TopStordata'
receivers=$(/TopStor/etcdget.py $leaderip Partner _Receiver)
echo "[INFO] Receivers fetched: $receivers"

if [[ $receivers == '_1' ]]; then
    echo "[WARN] --- no receivers....exiting"
    exit
fi

echo "========================================="
echo "--------- Looping over each receiver ----"

# Convert receivers into an array if needed
IFS=$'\n' read -r -d '' -a receivers_array <<< "$(echo "$receivers")"

for receiver in "${receivers_array[@]}"; do
    # Reset state variables for each receiver
    Lremote='needed'
    readyport='0'
    failednode='NOfailedNode'
    
    echo "-----------------------------------------"
    echo "[LOOP] Processing receiver: $receiver"
    
    cluster=$(echo $receiver | awk -F'/' '{print $2}' | awk -F"'," '{print $1}')
    clusterip=$(echo $receiver | awk -F"', '" '{print$2}' | awk -F"/" '{print $1}')
    phrase=$(echo $receiver | awk -F"/" '{print$5}' | awk -F"'" '{print $1}')
    repliport=$(echo $receiver | awk -F"/" '{print$4}')
    
    echo "[INFO] Parsed cluster=$cluster"
    echo "[INFO] Parsed clusterip=$clusterip"
    echo "[INFO] Parsed phrase=$phrase"
    echo "[INFO] Parsed repliport=$repliport"
    
    # Check if tunnel is already running and working
    tasks=$(ps -ef | egrep 'Rremote' | grep ssh$cluster)
    echo "[DEBUG] Found running tasks for Rremote: $tasks"
    
    echo tt$tasks | grep $cluster >/dev/null
    if [ $? -eq 0 ]; then
        echo "[INFO] --------- remote file is already loaded. Checking if the other end works"
        readyport=$(echo $tasks | awk -F":$leaderip" '{print $1}' | awk -F":" '{print $NF}')
        echo "[INFO] Extracted readyport=$readyport"
        
        testport=$(/TopStor/etcdgetnoport.py $leaderip $readyport ready --prefix)
        echo "[INFO] testport=$testport"
        
        echo $testport | grep _1 >/dev/null
        if [ $? -eq 0 ]; then
            echo "[WARN] -------- loaded files are failing, setting failednode and leaving Lremote=needed"
            failednode=$(echo $tasks | awk -F"$cluster/" '{print $2}' | awk '{print $1}')
            echo "[WARN] failednode=$failednode"
            Lremote='needed'
        else
            echo "[INFO] Tunnel is working successfully, progressing to readyonly check"
            Lremote='continue'
        fi
    fi
    
    echo "[LOOP] Entering main loop with Lremote=$Lremote"
    
    while [[ $Lremote == 'needed' ]]; do
        echo "[LOOP] --- Lremote still needed, analyzing situation"
        
        # Kill any old, lingering processes for this cluster
        kill -9 $(ps -eo pid,args | egrep 'Rremote|Lremote' | grep $cluster | awk '{print $1}') 2>/dev/null
        echo "[ACTION] Killed old Rremote/Lremote processes for $cluster"
        
        # Check if directory exists - OLD SCRIPT LOGIC
        if [ ! -d "$current_dir/$cluster" ]; then
            echo "[INFO] Directory $current_dir/$cluster does not exist - FIRST TIME INITIALIZATION"
            /TopStor/etcdput.py $etcdip replinextport 2380
            Lremote='initialize'
            break  # Exit while loop to hit initialization block
        fi
        
        # Discover existing tunnel script files - OLD SCRIPT LOGIC
        files=$(ls $current_dir/$cluster/ 2>/dev/null | egrep Rremote | grep $cluster)
        ofiles=$(ls $current_dir/$cluster/ 2>/dev/null | egrep Rremote | grep $cluster | egrep -v "$failednode")
        
        echo "[DEBUG] All Rremote files: $files"
        echo "[DEBUG] Valid Rremote files (excluding failed): $ofiles"
        
        echo file$ofiles | grep $cluster >/dev/null
        if [ $? -eq 0 ]; then
            # We have existing scripts for other nodes - try to use them first
            echo "[INFO] -------- Found existing tunnel scripts, attempting to use them"
            
            Lremote_script=$(ls $current_dir/$cluster/ | egrep Lremote | egrep -v "$failednode" | head -1)
            Rremote_script=$(ls $current_dir/$cluster/ | egrep Rremote | egrep -v "$failednode" | head -1)
            
            if [ -n "$Lremote_script" ] && [ -n "$Rremote_script" ]; then
                echo "[ACTION] Launching existing tunnels: $Lremote_script and $Rremote_script"
                $current_dir/$cluster/$Lremote_script & disown
                $current_dir/$cluster/$Rremote_script & disown
                sleep 2
                
                tasks=$(ps -ef | grep Rremote | grep ssh$cluster)
                readyport=$(echo $tasks | awk -F":$leaderip" '{print $1}' | awk -F":" '{print $NF}')
                testport=$(/TopStor/etcdgetnoport.py $leaderip $readyport ready --prefix)
                
                echo "[INFO] testport after launching: $testport"
                echo testport$testport | grep _1 >/dev/null
                if [ $? -eq 0 ]; then
                    # Test failed - mark this node as failed
                    echo "[ERROR] Test failed for existing scripts"
                    failed_node_name=$(echo $Rremote_script | awk -F"Receiver_" '{print $2}' | awk -F"_" '{print $1}')
                    failednode="${failednode}|${failed_node_name}"
                    echo "[WARN] failednode=$failednode"
                    Lremote='needed'
                    continue
                else
                    if [[ $testport == '' ]]; then
                        echo "[WARN] Empty testport, retrying..."
                        continue
                    else
                        echo "[SUCCESS] Existing tunnel working successfully"
                        Lremote='continue'
                        break
                    fi
                fi
            else
                echo "[WARN] Could not find valid existing scripts, will try failover"
            fi
        fi
        
        # If we're still here, either no existing scripts worked or none exist
        # Check if ANY files exist at all
        echo file$files | grep $cluster >/dev/null
        if [ $? -ne 0 ]; then
            # No files exist at all - need initialization
            echo "[INFO] ----------------------- No files are initialized before, need to start from scratch"
            /TopStor/etcdput.py $etcdip replinextport 2380
            Lremote='initialize'
            break  # Exit while loop to hit initialization block
        fi
        
        # Files exist but all nodes failed - Try NEW SCRIPT FAILOVER LOGIC
        echo "[INFO] ========== Attempting Dynamic Failover =========="
        echo "[ACTION] Discovering current primary node from remote cluster at $clusterip..."
        
        new_primary_info=$(/TopStor/etcdget.py $clusterip ready --prefix)
        new_primary_ip=$(echo "$new_primary_info" | awk -F"'" '{print $4}')
        
        echo "[INFO] Discovered primary node: $new_primary_ip"
        
        if [ -z "$new_primary_ip" ]; then
            echo "[ERROR] No ready node found on the remote cluster. It may be completely down."
            Lremote='receiver is down'
            break
        fi
        
        # Check if this node already failed
        echo "$failednode" | grep -w "$new_primary_ip" > /dev/null
        if [ $? -eq 0 ]; then
            echo "[ERROR] The discovered node ($new_primary_ip) is in the failed list. Remote cluster appears down."
            Lremote='receiver is down'
            break
        fi
        
        # Perform key exchange for the new node
        echo "[ACTION] Performing key exchange for $new_primary_ip"
        echo "[CMD] /TopStor/replisubmitkeys.py $cluster $new_primary_ip yes $myhost $myhostip $leaderip $repliport $phrase"
        /TopStor/replisubmitkeys.py $cluster $new_primary_ip "yes" $myhost $myhostip $leaderip $repliport $phrase
        
        if [ $? -ne 0 ]; then
            echo "[ERROR] Key exchange failed for $new_primary_ip. Marking as failed."
            failednode="${failednode}|${new_primary_ip}"
            continue
        fi
        
        # Get a fresh port allocation for the new node
        echo "[ACTION] Allocating new port for failover tunnel..."
        new_readyport=$(/TopStor/etcdget.py $etcdip replinextport)
        echo "[INFO] Allocated new readyport=$new_readyport"
        
        # Generate new tunnel scripts for this node with the NEW port
        echo "[ACTION] Generating tunnel scripts for $new_primary_ip with port $new_readyport..."
        /TopStor/remotetunneladd.sh "$cluster" "$clusterip" "$leaderip" "$new_primary_ip" "$repliport" "$new_readyport"       
 
        sleep 1
        
        # Find the newly created scripts
        Lremote_script=$(ls $current_dir/$cluster/ | egrep Lremote | grep "$new_primary_ip")
        Rremote_script=$(ls $current_dir/$cluster/ | egrep Rremote | grep "$new_primary_ip")
        
        if [ -z "$Lremote_script" ] || [ -z "$Rremote_script" ]; then
            echo "[ERROR] Failed to generate/find scripts for $new_primary_ip"
            failednode="${failednode}|${new_primary_ip}"
            continue
        fi
        
        # Launch the new tunnels
        echo "[ACTION] Launching new tunnels using $Lremote_script and $Rremote_script"
        $current_dir/$cluster/$Lremote_script & disown
        $current_dir/$cluster/$Rremote_script & disown
        sleep 2
        
        # Verify the new connection
        tasks=$(ps -ef | grep Rremote | grep "ssh$cluster")
        readyport=$(echo $tasks | awk -F":$leaderip" '{print $1}' | awk -F":" '{print $NF}')
        echo "[INFO] Updated readyport from new process: $readyport"
        testport=$(/TopStor/etcdgetnoport.py $leaderip $readyport ready --prefix)
        
        echo "[INFO] testport after failover: $testport"
        echo "testport$testport" | grep _1 >/dev/null
        if [ $? -eq 0 ] || [[ $testport == '' ]]; then
            echo "[ERROR] Test failed for new node $new_primary_ip"
            failednode="${failednode}|${new_primary_ip}"
            Lremote='needed'
            continue
        else
            echo "[SUCCESS] ===== Failover to $new_primary_ip complete ====="
            Lremote='continue'
            break
        fi
    done
    
    echo "[CHECK] After main loop, Lremote=$Lremote"
    
    # Handle initialization - OLD SCRIPT LOGIC
    echo $Lremote | egrep 'initialize' >/dev/null
    if [ $? -eq 0 ]; then
        echo "[ACTION] ======== INITIALIZING REMOTE PARTNER ========"
        leader=$(/TopStor/etcdget.py $leaderip leader)
        myhost=$(hostname)
        myhostip=$(/TopStor/etcdget.py $leaderip clusternodeip)
        
        echo $leader | grep $myhost >/dev/null
        if [ $? -eq 0 ]; then
            etcdip=$leaderip
        else
            etcdip=$(/TopStor/etcdget.py $leaderip clusternodeip)
        fi
        
        echo "[CMD] /TopStor/initreplipartner.py init $leaderip $myhostip $myhost $cluster $clusterip $repliport $phrase"
        /TopStor/initreplipartner.py init $leaderip $myhostip $myhost $cluster $clusterip $repliport $phrase
    fi
    
    # Handle readyonly checks - OLD SCRIPT LOGIC
    echo $Lremote | grep continue >/dev/null
    if [ $? -eq 0 ]; then
        echo "[ACTION] ============ Checking new remote ready nodes ============"
        echo "[CMD] /TopStor/initreplipartner.py readyonly $cluster $clusterip $myhost $myhostip $leaderip $repliport $phrase $readyport"
        /TopStor/initreplipartner.py readyonly $cluster $clusterip $myhost $myhostip $leaderip $repliport $phrase $readyport
    fi

    # the receiver's pull of users/groups/snapshots runs on ITS LEADER against its own cluster address: the reverse tunnel (-R)
    # has to end on the leader node (a tunnel to another node cannot bind the cluster address), so the tunnel scripts of the
    # partner's leader are started as well, whichever node was used first
    partnerleader=$(/TopStor/etcdget.py $clusterip leader)
    partnerleaderip=$(/TopStor/etcdget.py $clusterip ready/$partnerleader)
    if [ -n "$partnerleaderip" ] && [ "$partnerleaderip" != "_1" ] && [ -f $current_dir/$cluster/Rremote_${cluster}_${partnerleaderip}_.sh ]; then
        ps -ef | grep Rremote | grep ssh$cluster | grep -q "$partnerleaderip Rremote" || {
            echo "[ACTION] starting the tunnels to the partner leader $partnerleader ($partnerleaderip)"
            $current_dir/$cluster/Lremote_${cluster}_${partnerleaderip}_.sh & disown
            $current_dir/$cluster/Rremote_${cluster}_${partnerleaderip}_.sh & disown
        }
    fi
    
done

echo "========== Script Completed =========="
