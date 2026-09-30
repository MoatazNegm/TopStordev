#!/bin/sh
# ---------------------------------------------------------------------------
# proxypush.sh <branch>
#
# Copy one branch of all three projects from abdopuppet out to github.
#
# This container is only a relay, so the script never looks at, checks out,
# resets, cleans, stashes or deletes anything in /TopStor, /pace or
# /topstorweb.  Every project is copied through its own throwaway bare
# repository, so a branch that is checked out in a worktree, a dirty working
# tree, a leftover temp branch, a stale local copy or an ambiguous branch name
# cannot affect the result.  The old version broke on exactly those: it tried
# to delete the branch locally, which fails when a worktree has it checked out.
#
# How it works, per project:
#   1. ask abdopuppet and github what commit the branch is at   (cheap, no
#      objects moved).  If they already agree, that project is skipped and
#      nothing is downloaded.
#   2. otherwise fetch just that one branch, shallowly, into a scratch repo
#   3. push that ref straight across to github
#   4. if github rejects the shallow push, deepen the history and retry once
#
# overrides (environment):
#   PROXY_BRANCH      branch to copy, if not given on the command line
#   PROXY_PROJECTS    space separated project names
#   PROXY_ABDOPUPET   host holding the bare repositories
#   PROXY_GITHUB      github account / organisation
#   PROXY_DRYRUN      1 = report what would happen, never push
# ---------------------------------------------------------------------------

PROJECTS=${PROXY_PROJECTS:-"TopStordev HC TopStorWeb"}
ABDOPUPET=${PROXY_ABDOPUPET:-10.11.11.252}
GITHUB_USER=${PROXY_GITHUB:-MoatazNegm}
DRYRUN=${PROXY_DRYRUN:-0}
WORKROOT=${PROXY_WORKROOT:-/tmp/proxypush}

branch=$1
[ -n "$branch" ] || branch=$PROXY_BRANCH

if [ -z "$branch" ]; then
	echo "usage: proxypush.sh <branch>" >&2
	echo "  copies that branch of every project from $ABDOPUPET out to github" >&2
	exit 1
fi

# github needs a working resolver; the old script forced this too
if [ -w /etc/resolv.conf ]; then
	echo 'nameserver 8.8.8.8' > /etc/resolv.conf 2>/dev/null
fi

ok=0
skipped=0
missing=0
failed=0

for project in $PROJECTS; do
	from_url="git://$ABDOPUPET/$project.git"
	to_url="https://github.com/$GITHUB_USER/$project.git"

	echo
	echo '###########################################'
	echo "  $project"
	echo "  from : $from_url"
	echo "  to   : $to_url"

	# ---- 1. what is where, without moving any objects ----
	src_sha=`timeout 60 git ls-remote --heads "$from_url" "$branch" 2>/dev/null | awk 'NR==1 { print $1 }'`
	if [ -z "$src_sha" ]; then
		echo "  abdopuppet has no branch '$branch' - nothing to copy"
		missing=`expr $missing + 1`
		continue
	fi
	dst_sha=`timeout 60 git ls-remote --heads "$to_url" "$branch" 2>/dev/null | awk 'NR==1 { print $1 }'`
	echo "  abdopuppet : $src_sha"
	if [ -z "$dst_sha" ]; then
		echo "  github     : (no such branch yet)"
	elif [ "$dst_sha" = "$src_sha" ]; then
		echo "  github     : $dst_sha"
		echo "  already identical - nothing to do for this project"
		skipped=`expr $skipped + 1`
		continue
	else
		echo "  github     : $dst_sha  (different - it will be updated)"
	fi

	if [ "$DRYRUN" = 1 ]; then
		echo "  PROXY_DRYRUN=1 - would push $src_sha, not pushing"
		continue
	fi

	# ---- a throwaway bare repo, private to this run ----
	scratch="$WORKROOT/$project.$$"
	rm -rf "$scratch"
	mkdir -p "$scratch" || { failed=`expr $failed + 1`; continue; }
	git init -q --bare "$scratch/relay.git" || {
		echo "  could not create a scratch repository"
		failed=`expr $failed + 1`
		rm -rf "$scratch"
		continue
	}
	cd "$scratch/relay.git" || { failed=`expr $failed + 1`; continue; }
	git remote add abdopuppet "$from_url" >/dev/null 2>&1
	git remote add github "$to_url" >/dev/null 2>&1

	# ---- 2. shallow fetch of the one branch we need ----
	ref="+refs/heads/$branch:refs/heads/$branch"
	echo "  fetching $branch (shallow) ..."
	if ! timeout 300 git fetch --no-tags --depth 1 abdopuppet "$ref" > "$scratch/fetch" 2>&1; then
		echo "  shallow fetch failed - fetching the full history instead ..."
		if ! timeout 900 git fetch --no-tags abdopuppet "$ref" > "$scratch/fetch" 2>&1; then
			echo "  FAILED to fetch $branch from $ABDOPUPET"
			tail -5 "$scratch/fetch" | sed 's/^/     /'
			failed=`expr $failed + 1`
			cd /; rm -rf "$scratch"
			continue
		fi
	fi
	got=`git rev-parse "refs/heads/$branch" 2>/dev/null`
	if [ "$got" != "$src_sha" ]; then
		echo "  FAILED: fetched $got but abdopuppet said $src_sha"
		failed=`expr $failed + 1`
		cd /; rm -rf "$scratch"
		continue
	fi
	echo "  have $got locally"

	# ---- 3. push the ref straight across ----
	if timeout 600 git push github "$ref" > "$scratch/push" 2>&1; then
		echo "  PUSHED $branch to github"
		ok=`expr $ok + 1`
	else
		# ---- 4. a shallow push can be refused when github lacks the
		#         history.  Deepen and try once more. ----
		echo "  push refused, deepening the history and trying once more ..."
		sed 's/^/     /' "$scratch/push" | head -6
		if timeout 900 git fetch --no-tags --deepen 200 abdopuppet "$ref" > "$scratch/deepen" 2>&1; then
			if timeout 600 git push github "$ref" > "$scratch/push2" 2>&1; then
				echo "  PUSHED $branch to github on the second attempt"
				ok=`expr $ok + 1`
			else
				echo "  FAILED to push $branch to github"
				tail -8 "$scratch/push2" | sed 's/^/     /'
				failed=`expr $failed + 1`
			fi
		else
			echo "  FAILED to deepen the history"
			tail -5 "$scratch/deepen" | sed 's/^/     /'
			failed=`expr $failed + 1`
		fi
	fi

	cd /
	rm -rf "$scratch"
done

echo
echo '###########################################'
echo "  branch $branch"
echo "  pushed to github   : $ok"
echo "  already identical  : $skipped"
[ "$missing" -gt 0 ] && echo "  not on abdopuppet  : $missing"
[ "$failed" -gt 0 ] && echo "  failed             : $failed"
echo
if [ "$failed" -gt 0 ]; then
	echo "  finished, with errors"
	exit 1
fi
echo "  finished"
exit 0
