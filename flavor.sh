#!/bin/sh
# flavor.sh -- source it:  [ -f /TopStor/flavor.sh ] && . /TopStor/flavor.sh
#
# Decides at run time whether this node is the CONTAINER flavour (the zfs container used for
# development) or a PHYSICAL server, so one code base serves both:
#   is_container    true in the container flavour, false on a physical server
#   $DOCKER_NET     docker network of the support containers: intdns-net (container) or bridge0 (physical)
#
# Container = /.dockerenv or /run/.containerenv exists, or the interface eth10 exists (the zfs
# entrypoint renames the image's bond0 to eth10; a physical server has no eth10).
# Override for tests:  TOPSTOR_FLAVOR=container|physical
#
# Safe by design: when this file is missing, callers use `is_container 2>/dev/null` / `${DOCKER_NET:-bridge0}`,
# which falls back to the physical behaviour.
if [ -z "$TOPSTOR_FLAVOR" ]; then
	if [ -e /.dockerenv ] || [ -e /run/.containerenv ] || [ -d /sys/class/net/eth10 ]; then
		TOPSTOR_FLAVOR=container
	else
		TOPSTOR_FLAVOR=physical
	fi
fi
export TOPSTOR_FLAVOR
is_container() { [ "$TOPSTOR_FLAVOR" = container ]; }
if is_container; then DOCKER_NET=intdns-net; else DOCKER_NET=bridge0; fi
export DOCKER_NET
