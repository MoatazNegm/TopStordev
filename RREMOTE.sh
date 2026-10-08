#!/bin/bash
ssh -oStrictHostKeyChecking=no -p secureport -i /TopStordata/receiver/remotenode   -N -R remotecluster:tunnelport:mycluster:2379 remotenode Rremote sshreceiver
if [ $? -ne 0 ];
then
	echo Somthing went wrong, removing active links to this remote node
	kill -9 `pgrep Rremote  -a | grep remotenode  | awk '{print $1}'`
fi
#_REMOTE_ssh -p secureport -i /TopStordata/remotenode/remotenode remotenode ls
