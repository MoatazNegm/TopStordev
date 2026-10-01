#!/bin/sh
# ---------------------------------------------------------------------------
# systempush.sh <newbranch>
#
# Commit everything in all three projects, move onto the new branch name and
# push it.
#
# Per project (TopStor, pace, topstorweb):
#   1. git add --all          every file, including ones not tracked yet
#   2. drop what must not be committed:
#        __pycache__ junk          -- deleted from disk as well
#        the SPD_EXCLUDE files     -- untracked, but kept on disk
#   3. commit                 always, even when there is nothing to commit
#   4. create <newbranch> at that commit and check it out
#   5. push <newbranch> to origin
#
# Nothing is merged and nothing is pulled.  The new branch simply starts at the
# commit you just made, exactly like the old version did.
#
# Shallow aware.  A shallow repository can be refused by the server with
# "shallow update not allowed", because the pack it produces is marked shallow.
# When that happens the history is deepened once and the push is retried, so it
# fixes itself instead of stopping.
#
# environment:
#   SPD_PUSH_FORCE=1   pass --force-with-lease to the push
#   SPD_EXCLUDE        files to untrack and ignore before committing.
#                      Default: quickstor-ui.tar.gz.  These are left on disk.
#   SPD_PROJECTS       space separated project directory names
#   SPD_ROOT           prefix to put in front of every path (default none)
# ---------------------------------------------------------------------------

SPD_PUSH_FORCE=${SPD_PUSH_FORCE:-0}
SPD_EXCLUDE=${SPD_EXCLUDE:-'quickstor-ui.tar.gz'}
SPD_PROJECTS=${SPD_PROJECTS:-'TopStor pace topstorweb'}
SPD_ROOT=${SPD_ROOT:-}
PROJECTS=$SPD_PROJECTS

fnpush() {
	branch=$1

	pushflags=
	if [ "$SPD_PUSH_FORCE" = "1" ]; then
		pushflags=--force-with-lease
	fi

	log1=/tmp/spdpush1.$$
	log2=/tmp/spdpush2.$$

	echo "  pushing $branch to origin"
	if git push $pushflags origin "$branch" > "$log1" 2>&1; then
		sed 's/^/  | /' "$log1"
		rm -f "$log1"
		sync
		return 0
	fi
	sed 's/^/  | /' "$log1"

	# A shallow pack is refused with "shallow update not allowed".  Deepen once
	# and try again.  Any other rejection is a real disagreement with the remote
	# and must not be papered over by deepening -- say so and stop.
	if [ -f .git/shallow ] && grep -qi shallow "$log1"; then
		echo "  refused because the repository is shallow"
		echo "  deepening the history and trying once more ..."
		git fetch --no-tags --unshallow origin >/dev/null 2>&1 || git fetch --no-tags origin
		if git push $pushflags origin "$branch" > "$log2" 2>&1; then
			sed 's/^/  | /' "$log2"
			rm -f "$log1" "$log2"
			echo "  pushed on the second attempt"
			sync
			return 0
		fi
		sed 's/^/  | /' "$log2"
	fi

	rm -f "$log1" "$log2"
	echo "  ERROR: could not push $branch to origin"
	echo "         the branch was committed and checked out locally, so nothing"
	echo "         is lost.  Resolve the difference with the remote and push again."
	return 1
}

fnupdate() {
	branch=$1
	dir=`pwd`

	if [ ! -e .git ]; then
		echo "  $dir is not a git repository"
		return 1
	fi

	# ---- 1 and 2. stage everything, minus what must never be committed ---
	git add --all

	# __pycache__ turns up at any depth, so a bare '__py*' pathspec is not
	# enough -- it only ever matches the top level.  :(glob)** reaches them all.
	git rm -rq --ignore-unmatch -- ':(glob)**/__py*' >/dev/null 2>&1
	find . -name '.git' -prune -o -name '__py*' -prune -exec rm -rf {} + 2>/dev/null

	# Build artefacts: untracked, but deliberately LEFT ON DISK.  These are
	# files you still want on the node, you just do not want them in git --
	# quickstor-ui.tar.gz alone is 75 MB, which is 85% of the tree and is
	# re-uploaded to github on every single branch, making each push take
	# about a minute and a half.
	#
	# .gitignore does NOT stop this on its own: once a file is tracked the
	# ignore rules are never applied to it again.  So it has to be removed
	# from the index as well, which is what this does.
	for pat in $SPD_EXCLUDE; do
		if git ls-files --error-unmatch -- "$pat" >/dev/null 2>&1; then
			git rm -rq --cached --ignore-unmatch -- "$pat" >/dev/null 2>&1
			echo "  no longer tracking $pat (the file is still on disk)"
		fi
		if [ -e "$pat" ] && ! grep -qxF "$pat" .gitignore 2>/dev/null; then
			echo "$pat" >> .gitignore
			echo "  added $pat to .gitignore"
		fi
	done

	git add --all

	if git diff --cached --quiet; then
		echo "  nothing to commit -- making an empty commit anyway"
	else
		echo "  committing the changes"
	fi

	# --allow-empty keeps the old behaviour of always producing a commit
	if ! git commit --allow-empty -m 'fixing'; then
		echo "  ERROR: the commit failed in $dir"
		return 1
	fi

	# ---- 3. the new branch name, starting at that commit -----------------
	commit=`git rev-parse HEAD`
	if git rev-parse --verify --quiet "refs/heads/$branch" >/dev/null; then
		echo "  $branch already exists -- moving it to $commit"
		git checkout -B "$branch" || {
			echo "  ERROR: could not check out $branch"
			return 1
		}
	else
		echo "  creating $branch at $commit"
		git checkout -b "$branch" || {
			echo "  ERROR: could not create $branch"
			return 1
		}
	fi

	# ---- 4. push ---------------------------------------------------------
	fnpush "$branch" || return 1

	echo "  $branch is at $commit"
	return 0
}

branch=$1
if [ -z "$branch" ]; then
	echo "usage: $0 <newbranch>"
	echo "  commits everything, moves onto <newbranch> and pushes it"
	exit 1
fi

echo "systempush: committing everything, moving onto $branch and pushing it"

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
if [ -z "$SPD_ROOT" ]; then
	cd /TopStor 2>/dev/null
	if docker ps 2>/dev/null | grep -q software; then
		myhost=`docker exec etcdclient /TopStor/etcdgetlocal.py clusternode`
		leaderip=`docker exec etcdclient /TopStor/etcdgetlocal.py leaderip`
		stamp=`date +%s`
		/TopStor/etcddel.py $leaderip sync/cversion --prefix
		/TopStor/etcdput.py $leaderip sync/cversion/_${branch}__/request cversion_$stamp
		/TopStor/etcdput.py $leaderip sync/cversion/_${branch}__/request/$myhost cversion_$stamp
		/TopStor/myrepopush.sh $branch
	fi
else
	echo "  SPD_ROOT is set .... skipping the cluster sync"
fi

echo
echo '###########################################'
for job in $PROJECTS; do
	cd "$SPD_ROOT/$job" 2>/dev/null || continue
	echo "$job : `git show --abbrev-commit | grep commit | head -1`"
done

echo
if [ "$rc" -ne 0 ]; then
	echo "finished, with errors"
	exit 1
fi
echo "finished"
exit 0
