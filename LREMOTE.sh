#!/bin/bash
ssh -oStrictHostKeyChecking=no -p secureport -i /TopStordata/receiver/remotenode   -N -L mycluster:tunnelport:remotecluster:2379 remotenode Lremote sshreceiver
if [ $? -ne 0 ];
then
	echo Somthing went wrong, removing active links to this remote node
	kill -9 `pgrep Lremote  -a | grep remotenode | awk '{print $1}'`
fi
#_REMOTE_ssh -p secureport -i /TopStordata/remotenode/remotenode remotenode ls
