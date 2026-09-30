#!/bin/sh
# ---------------------------------------------------------------------------
# proxyupdate.sh <branch>
#
# Copy one branch of all three projects from github back out to abdopuppet.
# This is the mirror image of proxypush.sh.
#
# The branch is taken from github EXACTLY AS IT IS.  It is never merged with,
# rebased onto, or combined with whatever branch happens to be checked out in
# this container -- the current branch is irrelevant to the result.  To make
# that true by construction the script never looks at, checks out, resets,
# cleans, stashes or deletes anything in /TopStor, /pace or /topstorweb.  Every
# project is copied through its own throwaway bare repository.
#
# The old version of this script worked on the local repositories instead.  It
# had three problems that this one does not:
#   * it had to delete the branch locally before it could re-create it, which
#     fails whenever a worktree has that branch checked out
#   * it left the repositories in /TopStor, /pace and /topstorweb sitting on
#     the relayed branch, so a later systempull or systempush could pick the
#     wrong one up
#   * it chose the github side with 'git remote -v | grep github | head -1'.
#     In /TopStor_yousefwael02 and /TopStor_Ahmed395593 the remotes are named
#     QuickStor and remote, and BOTH urls contain the word github, so that
#     could pick the developer's own fork instead of MoatazNegm.  This script
#     names the account outright, so a copy meant for abdopuppet cannot land
#     in somebody's fork.
#
# Per project:
#   1. ask github and abdopuppet what commit the branch is at.  If they already
#      agree, that project is skipped and nothing is downloaded.
#   2. otherwise fetch just that one branch, shallowly, into a scratch repo
#   3. push that ref straight across to abdopuppet
#   4. if abdopuppet refuses the shallow push, deepen and retry once
#   5. ask abdopuppet what it has now, so the result is proven not assumed
#
# overrides (environment):
#   PROXY_BRANCH      branch to copy, if not given on the command line
#   PROXY_PROJECTS    space separated project names
#   PROXY_ABDOPUPET   host holding the bare repositories
#   PROXY_GITHUB      github account / organisation
#   PROXY_DRYRUN      1 = report what would happen, never push
#   PROXY_WORKROOT    where the scratch repositories are made
# ---------------------------------------------------------------------------

PROJECTS=${PROXY_PROJECTS:-"TopStordev HC TopStorWeb"}
ABDOPUPET=${PROXY_ABDOPUPET:-10.11.11.252}
GITHUB_USER=${PROXY_GITHUB:-MoatazNegm}
DRYRUN=${PROXY_DRYRUN:-0}
WORKROOT=${PROXY_WORKROOT:-/tmp/proxyrelay}

branch=$1
[ -n "$branch" ] || branch=$PROXY_BRANCH

if [ -z "$branch" ]; then
	echo "usage: proxyupdate.sh <branch>" >&2
	echo "  copies that branch of every project from github out to $ABDOPUPET," >&2
	echo "  exactly as it is, without merging with anything local" >&2
	exit 1
fi

branch_from_github() {
	project=$1
	GIT_URL="https://github.com/$GITHUB_USER/$project.git"
	GIT_SHA=`timeout 60 git ls-remote --heads "$GIT_URL" "$branch" 2>/dev/null | awk 'NR==1 { print $1 }'`
}

# abdopuppet answers on two url forms depending on which repository copy asks
pick_abdopuppet() {
	project=$1
	ABD_URL=
	ABD_SHA=
	for u in "git://$ABDOPUPET/$1.git" "http://$ABDOPUPET/git/$1.git"; do
		sha=`timeout 60 git ls-remote --heads "$u" "$branch" 2>/dev/null | awk 'NR==1 { print $1 }'`
		if [ -n "$sha" ]; then
			ABD_URL=$u
			ABD_SHA=$sha
			return 0
		fi
	done
	return 1
}

# github needs a working resolver
if [ -w /etc/resolv.conf ]; then
	echo 'nameserver 8.8.8.8' > /etc/resolv.conf 2>/dev/null
fi

ok=0
skipped=0
missing=0
failed=0

for project in $PROJECTS; do
	echo
	echo '###########################################'
	echo "  $project"

	# ---- 1. what is where, without moving any objects ----
	branch_from_github "$project"
	if [ -z "$GIT_SHA" ]; then
		echo "  github has no branch '$branch' for $GITHUB_USER/$project - nothing to copy"
		missing=`expr $missing + 1`
		continue
	fi
	src_url=$GIT_URL
	src_sha=$GIT_SHA

	if pick_abdopuppet "$project"; then
		dst_sha=$ABD_SHA
		dst_url=$ABD_URL
	else
		dst_sha=
		dst_url="git://$ABDOPUPET/$project.git"
	fi

	echo "  from : $src_url"
	echo "  to   : $dst_url"
	echo "  github     : $src_sha"
	if [ -z "$dst_sha" ]; then
		echo "  $ABDOPUPET : (no such branch yet)"
	elif [ "$dst_sha" = "$src_sha" ]; then
		echo "  $ABDOPUPET : $dst_sha"
		echo "  already identical - nothing to do for this project"
		skipped=`expr $skipped + 1`
		continue
	else
		echo "  $ABDOPUPET : $dst_sha  (different - it will be updated)"
	fi

	if [ "$DRYRUN" = 1 ]; then
		echo "  PROXY_DRYRUN=1 - would push $src_sha to $ABDOPUPET, not pushing"
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
	git remote add github "$src_url" >/dev/null 2>&1
	git remote add abdopuppet "$dst_url" >/dev/null 2>&1

	# ---- 2. shallow fetch of the one branch we need ----
	ref="+refs/heads/$branch:refs/heads/$branch"
	echo "  fetching $branch (shallow) ..."
	if ! timeout 300 git fetch --no-tags --depth 1 github "$ref" > "$scratch/fetch" 2>&1; then
		echo "  shallow fetch failed - fetching the full history instead ..."
		if ! timeout 900 git fetch --no-tags github "$ref" > "$scratch/fetch" 2>&1; then
			echo "  FAILED to fetch $branch from github"
			tail -5 "$scratch/fetch" | sed 's/^/     /'
			failed=`expr $failed + 1`
			cd /; rm -rf "$scratch"
			continue
		fi
	fi
	got=`git rev-parse "refs/heads/$branch" 2>/dev/null`
	if [ "$got" != "$src_sha" ]; then
		echo "  FAILED: fetched $got but github said $src_sha"
		failed=`expr $failed + 1`
		cd /; rm -rf "$scratch"
		continue
	fi
	echo "  have $got locally, exactly as github has it"

	# ---- 3. push the ref straight across ----
	if timeout 600 git push abdopuppet "$ref" > "$scratch/push" 2>&1; then
		echo "  PUSHED $branch to $ABDOPUPET"
		ok=`expr $ok + 1`
	elif timeout 900 git fetch --no-tags --deepen 200 github "$ref" > "$scratch/deepen" 2>&1 &&
	     timeout 600 git push abdopuppet "$ref" > "$scratch/push2" 2>&1; then
		# ---- 4. a shallow pack is refused when the far side lacks history ----
		echo "  push refused, deepened the history, PUSHED on the second attempt"
		ok=`expr $ok + 1`
	else
		echo "  FAILED to push $branch to $ABDOPUPET"
		[ -f "$scratch/push" ] && sed 's/^/     /' "$scratch/push" | head -6
		[ -f "$scratch/push2" ] && tail -6 "$scratch/push2" | sed 's/^/     /'
		[ -f "$scratch/deepen" ] && tail -4 "$scratch/deepen" | sed 's/^/     /'
		failed=`expr $failed + 1`
	fi

	# ---- 5. prove abdopuppet really has it now ----
	cd /
	now=`timeout 60 git ls-remote --heads "$dst_url" "$branch" 2>/dev/null | awk 'NR==1 { print $1 }'`
	if [ "$now" = "$src_sha" ]; then
		echo "  verified: $ABDOPUPET now has $now"
	else
		echo "  *** $ABDOPUPET reports '$now', expected $src_sha"
		failed=`expr $failed + 1`
	fi
	rm -rf "$scratch"
done

echo
echo '###########################################'
echo "  branch $branch"
echo "  pushed to $ABDOPUPET : $ok"
echo "  already identical    : $skipped"
[ "$missing" -gt 0 ] && echo "  not on github        : $missing"
[ "$failed" -gt 0 ] && echo "  failed               : $failed"
echo
if [ "$failed" -gt 0 ]; then
	echo "  finished, with errors"
	exit 1
fi
echo "  finished"
exit 0
