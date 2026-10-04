#!/bin/sh
# myrepolib.sh -- sourced by myrepopush.sh, myrepopull.sh, systempush.sh and
# systempull.sh before they act on the cluster repos served by the `software`
# container (git over http: http://<node ip>/git/<repo>.git, bare repos under
# /root/gitrepo/git).

GITREPO_ROOT=${GITREPO_ROOT:-/root/gitrepo/git}

# software_ready <node ip>
# The software container must be running and its web server must answer.
# Waits a little for a container that is still starting. Returns 1 (with a
# message on stderr) when it is not usable, so callers can stop before touching
# anything.
software_ready() {
	_ip=$1
	if [ -z "$_ip" ]; then
		echo "  cannot determine this node's ip (is the etcdclient container up?)" >&2
		return 1
	fi
	if [ "`docker inspect -f '{{.State.Running}}' software 2>/dev/null`" != "true" ]; then
		echo "  the software container is not running (docker_setup.sh starts it)" >&2
		return 1
	fi
	_i=0
	while [ $_i -lt 15 ]; do
		_code=`curl -s -o /dev/null -m 3 -w '%{http_code}' "http://${_ip}/" 2>/dev/null`
		case $_code in
		''|000) ;;
		*) return 0 ;;
		esac
		_i=$((_i + 1))
		sleep 2
	done
	echo "  the software container is running but http://${_ip}/ does not answer" >&2
	return 1
}

# ensure_bare_repo <name.git>
# Create the bare repo under $GITREPO_ROOT when it is missing. An existing valid
# repo is left exactly as it is. A directory that is there but is not a bare repo
# is moved aside (never deleted) and replaced.
ensure_bare_repo() {
	_repo="$GITREPO_ROOT/$1"
	if [ -f "$_repo/HEAD" ] && [ -d "$_repo/objects" ]; then
		return 0
	fi
	if [ -e "$_repo" ]; then
		_aside="$_repo.broken-`date +%s`"
		echo "  $_repo is not a bare git repo -- moving it to $_aside"
		mv "$_repo" "$_aside" || return 1
	fi
	echo "  git repo $1 not found in $GITREPO_ROOT -- creating it"
	mkdir -p "$_repo" || return 1
	git init --bare "$_repo" >/dev/null || return 1
	chown -R 33:33 "$_repo"
}
