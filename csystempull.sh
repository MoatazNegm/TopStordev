#!/bin/sh
# csystempull.sh -- CONTAINER variant of systempull.sh (the plain script hands over to this one in the container
# flavour). Identical except for the software-container check: see csoftware_ready below.
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
#   SPD_SYNC=0          skip the cluster sync and the apply.d hooks (a node that is not in
#                       the cluster yet, e.g. joinpull.sh)
# ---------------------------------------------------------------------------

SPD_BASE=${SPD_BASE:-QSD5.179}
SPD_CLEAN=${SPD_CLEAN:-0}
SPD_PROJECTS=${SPD_PROJECTS:-'TopStor pace topstorweb'}
SPD_ROOT=${SPD_ROOT:-}
SPD_REMOTE=${SPD_REMOTE:-origin}
SPD_SYNC=${SPD_SYNC:-1}
# One-off bridge for topstorweb: dist/, plugins/ ... are tracked up to this branch and
# ignored (untracked) after it.  A node that went to a newer branch with an OLD pull
# script has lost them; the next pull (this script) goes through the bridge first.
SPD_BRIDGE=${SPD_BRIDGE:-QSD5.211}
SPD_BRIDGE_PROJECT=${SPD_BRIDGE_PROJECT:-topstorweb}
SPD_BRIDGE_MARK=${SPD_BRIDGE_MARK:-plugins}
PROJECTS=$SPD_PROJECTS

# csoftware_ready <node ip>
# Container flavour: the software container is a git daemon on port 9418 (git://<ip>/<repo>.git), not the
# httpd on port 80 of a physical node, so myrepolib.sh's software_ready (which probes http://<ip>/) never
# answers here. Same contract: 0 when usable, 1 with a message on stderr when not; waits for a container
# that has just started.
csoftware_ready() {
	_ip=$1
	if [ -z "$_ip" ]; then
		echo "  cannot determine this node's ip (is the etcdclient container up?)" >&2
		return 1
	fi
	if [ "`docker inspect -f '{{.State.Running}}' software 2>/dev/null`" != "true" ]; then
		echo "  the software container is not running (docker_setup.sh starts it)" >&2
		return 1
	fi
	_started=`docker inspect -f '{{.State.StartedAt}}' software 2>/dev/null`
	_up=$(( `date +%s` - `date -d "$_started" +%s 2>/dev/null || echo 0` ))
	_tries=8
	[ "$_up" -gt 120 ] && _tries=1
	_i=0
	while [ $_i -lt $_tries ]; do
		if timeout 5 git ls-remote "git://${_ip}/TopStordev.git" >/dev/null 2>&1; then
			return 0
		fi
		_i=$((_i + 1))
		if [ $_i -lt $_tries ]; then
			echo "  waiting for the software container to answer on git://${_ip}/ ($_i/$_tries) ..." >&2
			sleep 2
		fi
	done
	echo "  the software container is running but git://${_ip}/TopStordev.git does not answer" >&2
	return 1
}

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
	# ---- 2b. bridge: bring back the ignored directories a node has lost ----
	# Only when: this is the bridge project, the target does not track the marker
	# directory itself, the directory is missing or empty here, and the bridge branch exists.
	if [ "`basename "$dir"`" = "$SPD_BRIDGE_PROJECT" ] && [ "$branch" != "$SPD_BRIDGE" ] &&
	   [ -z "`ls -A "$SPD_BRIDGE_MARK" 2>/dev/null`" ] &&
	   [ -z "`git ls-tree --name-only "refs/remotes/$SPD_REMOTE/$branch" "$SPD_BRIDGE_MARK" 2>/dev/null`" ]; then
		echo "  $SPD_BRIDGE_MARK/ is missing here -- going through $SPD_BRIDGE first to bring it back"
		if git fetch --no-tags "$SPD_REMOTE" "+refs/heads/$SPD_BRIDGE:refs/remotes/$SPD_REMOTE/$SPD_BRIDGE" &&
		   [ -n "`git ls-tree --name-only "refs/remotes/$SPD_REMOTE/$SPD_BRIDGE" "$SPD_BRIDGE_MARK" 2>/dev/null`" ] &&
		   git checkout -f --detach "refs/remotes/$SPD_REMOTE/$SPD_BRIDGE" >/dev/null 2>&1; then
			echo "  $SPD_BRIDGE checked out -- $SPD_BRIDGE_MARK/ and the other ignored directories are back"
		else
			echo "  WARNING: bridge $SPD_BRIDGE not usable -- continuing without it"
		fi
	fi

	oldhead=`git rev-parse --verify --quiet HEAD`
	if ! git checkout -f -B "$branch" "refs/remotes/$SPD_REMOTE/$branch"; then
		echo "  ERROR: could not check out $branch"
		return 1
	fi
	# A path the old branch tracked but the new one ignores (dist/, plugins/ ...)
	# is deleted by the checkout as a "removed" file.  It must stay intact, so
	# put the committed content of the old branch back; it stays untracked.
	if [ -n "$oldhead" ] && [ "$oldhead" != "`git rev-parse HEAD`" ]; then
		keep=`git diff --name-only --diff-filter=D "$oldhead" HEAD 2>/dev/null |
			git check-ignore --no-index --stdin 2>/dev/null`
		if [ -n "$keep" ]; then
			echo "  keeping `echo "$keep" | wc -l` ignored file(s) the old branch tracked (dist/, plugins/ ...)"
			# xargs splits a long list into several runs, so each run gets its own tar
			echo "$keep" | tr '\n' '\0' |
				xargs -0 sh -c 'git archive "$0" -- "$@" | tar -x' "$oldhead"
		fi
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
elif csoftware_ready "`docker exec etcdclient /TopStor/etcdgetlocal.py clusternodeip`"; then
	echo "  running any needed scripts"
	leaderip=`docker exec etcdclient /TopStor/etcdgetlocal.py leaderip`
	leader=`docker exec etcdclient /TopStor/etcdgetlocal.py leader`
	myhost=`docker exec etcdclient /TopStor/etcdgetlocal.py clusternode`
	# Container variant: NO new sync/cversion request here (and no getcversion.sh, which posts one too).
	# pace/checksyncs.py answers a sync/cversion request by running systempull.sh; if the pull posted a
	# request itself, the nodes would re-trigger each other for ever and every round force-checks-out the
	# working trees (seen on 2026-10-05, a reset every ~20 s). A systempush.sh posts the one request that
	# makes the other nodes pull; a pull only records this node's own version.
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
	# per-branch hooks: apply.d/<branch>/pre_apply.sh and post_apply.sh of the branch just pulled
	# (stubs made by mkapplyhooks.sh).  A failing hook is reported, it does not stop the pull.
	for hook in pre_apply post_apply; do
		hf=${SPD_HOOKS_DIR:-/TopStor/apply.d}/$branch/$hook.sh
		if [ -f "$hf" ]; then
			echo "  running $hook for $branch"
			sh "$hf" "$branch" || { echo "  *** $hook for $branch failed"; rc=1; }
		else
			echo "  no $hook hook for $branch .... skipping"
		fi
	done
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
