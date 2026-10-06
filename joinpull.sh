#!/bin/sh
# joinpull.sh <primary-node-ip> <branch>
#
# Run by pace/senddiscovery.sh on a node that is joining the cluster, BEFORE it restarts:
# makes /TopStor, /pace and /topstorweb the same branch the primary serves from its software
# repo.  The pull itself is systempull.sh (branch taken exactly as it is, HEAD verified), run
# against a `leaderrepo` remote (container: git://IP/X.git, physical: http://IP/git/X.git) with
# SPD_SYNC=0 -- this node is not in the cluster yet.
[ -f /TopStor/flavor.sh ] && . /TopStor/flavor.sh
leaderip=$1
branch=$2
if [ -z "$leaderip" ] || [ ${#branch} -le 3 ]; then
	echo "usage: $0 <primary-node-ip> <branch>"
	exit 1
fi
for jobinfo in TopStor:TopStordev pace:HC topstorweb:TopStorweb; do
	job=${jobinfo%%:*}
	repo=${jobinfo##*:}.git
	cd /$job || continue
	git remote remove leaderrepo 2>/dev/null
	if is_container 2>/dev/null; then
		git remote add leaderrepo git://$leaderip/$repo
	else
		git remote add leaderrepo http://$leaderip/git/$repo
	fi
done
cd /TopStor
SPD_REMOTE=leaderrepo SPD_SYNC=0 /TopStor/systempull.sh $branch
rc=$?
[ -x /TopStor/pre_apply.sh ] && /TopStor/pre_apply.sh
exit $rc
