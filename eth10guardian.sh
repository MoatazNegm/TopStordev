#!/bin/bash
# Keeps eth10 enslaved to bond0. Any `nmcli conn up cmynode` (iscsiwatchdog.sh,
# cifs.sh, nfs*.sh, ...) makes NM recreate bond0, which releases eth10. Acts only
# once cmynode is fully activated, so it never races NM's own activation.
# Started once by docker_setup.sh.

ready() {
	[ -d /sys/class/net/eth10 ] && [ -d /sys/class/net/bond0 ] \
	&& ! grep -qw eth10 /sys/class/net/bond0/bonding/slaves 2>/dev/null \
	&& [ "$(nmcli -g GENERAL.STATE conn show cmynode 2>/dev/null)" = "activated" ]
}

while true; do
	if ready; then
		sleep 3
		if ready; then
			echo "$(date +%T) re-enslaving eth10 to bond0"
			ip addr flush dev eth10 2>/dev/null
			ip link set eth10 down
			ip link set eth10 master bond0
			ip link set eth10 up
		fi
	fi
	sleep 2
done
