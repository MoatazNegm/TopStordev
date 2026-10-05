#!/bin/sh
# --- FLAVOUR HAND-OVER: in the container flavour run the c- variant of this script ---
[ -f /TopStor/flavor.sh ] && . /TopStor/flavor.sh
if is_container 2>/dev/null && [ -f "/TopStor/c$(basename "$0")" ]; then
	exec "${BASH:-sh}" "/TopStor/c$(basename "$0")" "$@"
fi
# ---
# ---------------------------------------------------------------------------
# systempull.sh <branch>
#
# Take one branch from origin and make it the local branch, EXACTLY as it is.
#
# Per project (TopStor, pace, topstorweb):
#   1. fetch origin/<branch>
#   2. throw away every change made to the current branch
#   3. point the local <branch> at origin/<branch> -- no merge, no rebase, no
#      fast-forward, just the same commit
#   4. verify the local branch really is that same commit
#
# Shallow aware.  If a repository is shallow -- your image ships it shallow at
# QSD5.179 so it is a fraction of the size -- an ordinary fetch leaves the
# shallow boundary exactly where it is and only brings in what is missing
# above it, so the old history is never re-downloaded.  A branch that does not
# descend from the base is reported loudly here, instead of quietly producing
# an empty merge-base later on.
#
# environment:
#   SPD_BASE=<branch>   the base the image is built on (default QSD5.179).
#                       Use this to pull a branch that lives on a different
#                       line of history.
#   SPD_CLEAN=1         also delete untracked files, not just tracked changes
#   SPD_PROJECTS        space separated project directory names
#   SPD_ROOT            prefix to put in front of every path (default none)
#   SPD_REMOTE=<name>   git remote to pull from (default origin)
#   SPD_SYNC=0          skip the cluster sync and pre/post_apply (a node that is not in
#                       the cluster yet, e.g. joinpull.sh)
# ---------------------------------------------------------------------------

SPD_BASE=${SPD_BASE:-QSD5.179}
SPD_CLEAN=${SPD_CLEAN:-0}
SPD_PROJECTS=${SPD_PROJECTS:-'TopStor pace topstorweb'}
SPD_ROOT=${SPD_ROOT:-}
SPD_REMOTE=${SPD_REMOTE:-origin}
SPD_SYNC=${SPD_SYNC:-1}
PROJECTS=$SPD_PROJECTS

fnupdate() {
	branch=$1
	dir=`pwd`

	if [ ! -e .git ]; then
		echo "  $dir is not a git repository"
		return 1
	fi

	# ---- 1. fetch --------------------------------------------------------
	# In a shallow repository an ordinary fetch does NOT deepen the history:
	# git keeps the existing boundary and only brings in what is missing above
	# it.  That is the whole benefit of the base -- the old history is never
	# re-downloaded.  Do not pass --shallow-exclude here: on its own it fails
	# with "no commits selected for shallow requests", and combined with
	# --depth it fails with "deepen and deepen-since cannot be used together".
	shallow=
	if [ -f .git/shallow ]; then
		shallow=1
		echo "  shallow repository -- boundary stays at `head -1 .git/shallow`"
		echo "  the history below it is not re-downloaded"
	fi

	echo "  fetching $SPD_REMOTE/$branch"
	if ! git fetch --no-tags --prune "$SPD_REMOTE" \
			"+refs/heads/$branch:refs/remotes/$SPD_REMOTE/$branch"; then
		echo "  ERROR: could not fetch $branch from $SPD_REMOTE"
		return 1
	fi

	if ! git rev-parse --verify --quiet "refs/remotes/$SPD_REMOTE/$branch" >/dev/null; then
		echo "  ERROR: $SPD_REMOTE/$branch does not exist -- wrong branch name?"
		return 1
	fi

	# ---- 2. warn before the shallow boundary can bite --------------------
	if [ -n "$shallow" ]; then
		if git rev-parse --verify --quiet "refs/heads/$SPD_BASE" >/dev/null &&
		   git merge-base --is-ancestor "$SPD_BASE" "refs/remotes/$SPD_REMOTE/$branch" 2>/dev/null
		then
			echo "  $branch descends from $SPD_BASE -- merge-base stays correct"
		else
			echo "  *** WARNING: $branch does NOT descend from $SPD_BASE."
			echo "      merge-base will report nothing between it and anything"
			echo "      older, and git will call the two histories unrelated."
			echo "      Re-run with SPD_BASE=$branch to pull it properly."
		fi
	fi

	# ---- 3. discard local changes, take the branch as it is -------------
	# -B resets the branch to the given ref and checks it out.
	# -f throws local modifications away instead of refusing to switch.
	# There is deliberately no merge and no rebase anywhere in here.
	if ! git checkout -f -B "$branch" "refs/remotes/$SPD_REMOTE/$branch"; then
		echo "  ERROR: could not check out $branch"
		return 1
	fi
	git reset --hard --quiet
	if [ "$SPD_CLEAN" = "1" ]; then
		git clean -fdq
	fi

	# generated python junk must never end up in the tree.  It turns up at any
	# depth, so a bare '__py*' pathspec is not enough on its own.
	git rm -rq --ignore-unmatch -- ':(glob)**/__py*' >/dev/null 2>&1
	find . -name '.git' -prune -o -name '__py*' -prune -exec rm -rf {} + 2>/dev/null

	# ---- 4. prove the local branch is the same commit -------------------
	# NB: do not call these two 'want' or 'got' loosely -- 'want' is also the
	# name of the branch the caller wants every project to end up on, and sh
	# has no local variables, so reusing it here would clobber that.
	got=`git rev-parse HEAD`
	remote_sha=`git rev-parse refs/remotes/$SPD_REMOTE/$branch`
	if [ "$got" = "$remote_sha" ]; then
		echo "  $branch is now $got -- identical to $SPD_REMOTE/$branch"
	else
		echo "  *** ERROR: HEAD is $got but $SPD_REMOTE/$branch is $remote_sha"
		return 1
	fi

	sync
	return 0
}

branch=$1

case $branch in
samebranch|same)
	branch=`cd /TopStor 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null`
	if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
		echo "could not work out which branch you are on .... exiting"
		exit 1
	fi
	echo "using the branch you are on: $branch"
	;;
esac

if [ -z "$branch" ]; then
	echo "usage: $0 <branch>"
	echo "  replaces the local <branch> with origin/<branch>, exactly as it is"
	exit 1
fi

# the branch every project is expected to be sitting on when this finishes
want=$branch

echo "systempull: taking $branch from $SPD_REMOTE, as it is -- no merge, local changes discarded"

rc=0
for job in $PROJECTS; do
	echo
	echo '###########################################'
	echo "$job"
	if ! cd "$SPD_ROOT/$job"; then
		echo "  the directory $SPD_ROOT/$job is not found .... skipping"
		rc=1
		continue
	fi
	fnupdate "$branch" || rc=1
done

echo
echo '###########################################'
echo "  syncing the cluster"
# The cluster sync only makes sense on a real node, so SPD_ROOT overrides skip it.
if [ -n "$SPD_ROOT" ] || [ "$SPD_SYNC" = "0" ]; then
	echo "  SPD_ROOT/SPD_SYNC is set .... skipping the cluster sync"
elif ( . /TopStor/myrepolib.sh; software_ready "`docker exec etcdclient /TopStor/etcdgetlocal.py clusternodeip`" ); then
	echo "  running any needed scripts"
	leaderip=`docker exec etcdclient /TopStor/etcdgetlocal.py leaderip`
	leader=`docker exec etcdclient /TopStor/etcdgetlocal.py leader`
	myhost=`docker exec etcdclient /TopStor/etcdgetlocal.py clusternode`
	stamp=`date +%s`
	/TopStor/etcddel.py $leaderip sync/cversion --prefix
	/TopStor/etcdput.py $leaderip sync/cversion/_${branch}__/request cversion_$stamp
	/TopStor/etcdput.py $leaderip sync/cversion/_${branch}__/request/$myhost cversion_$stamp
	/TopStor/getcversion.sh $leaderip $leader $myhost
	cd /TopStor || exit 1
	commit=`git show --abbrev-commit | grep commit | head -1 | awk '{print $2}'`
	echo /TopStor/etcdput.py $leaderip cversion/$myhost $branch-$commit
	/TopStor/etcdput.py $leaderip cversion/$myhost $branch-$commit
	echo $leader | grep $myhost
	if [ $? -ne 0 ]; then
		myhostip=`docker exec etcdclient /TopStor/etcdgetlocal.py clusternodeip`
		echo ip=$myhostip
		/TopStor/etcdput.py $myhostip cversion/$myhost $branch-$commit
	fi
	/TopStor/myrepopush.sh $branch
else
	echo "  the software container is not ready .... skipping the cluster sync"
	rc=1
fi

if [ -z "$SPD_ROOT" ] && [ "$SPD_SYNC" != "0" ] && docker ps >/dev/null 2>&1; then
	if [ -e /TopStor/pre_apply.sh ]; then
		/TopStor/pre_apply.sh
	else
		echo "  pre_apply.sh is not present .... skipping"
	fi
	if [ -e /TopStor/post_apply.sh ]; then
		/TopStor/post_apply.sh
	else
		echo "  post_apply.sh is not present .... skipping"
	fi
fi

echo
echo '###########################################'
echo "  commits"
echo "  --------------------------------------------------------------"
printf "  %-11s %-16s %-42s %s\n" "project" "branch" "commit" "short"
for job in $PROJECTS; do
	if ! cd "$SPD_ROOT/$job" 2>/dev/null; then
		printf "  %-11s %s\n" "$job" "(directory not found)"
		continue
	fi
	b=`git rev-parse --abbrev-ref HEAD 2>/dev/null`
	s=`git rev-parse HEAD 2>/dev/null`
	k=`git rev-parse --short HEAD 2>/dev/null`
	flag=
	if [ -n "$want" ] && [ "$b" != "$want" ]; then
		flag="   <-- NOT the branch you asked for"
	fi
	printf "  %-11s %-16s %-42s %s%s\n" "$job" "$b" "$s" "$k" "$flag"
done
echo "  --------------------------------------------------------------"
echo "  every project should be sitting on $want"

echo
if [ "$rc" -ne 0 ]; then
	echo "finished, with errors"
	exit 1
fi
echo "finished"
exit 0
