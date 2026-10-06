#!/bin/sh
# ---------------------------------------------------------------------------
# proxypush.sh <branch>
#
# Copy one branch of all three projects from abdopuppet out to github.
#
# The branch is taken from abdopuppet EXACTLY AS IT IS, and github ends up
# holding the identical commit.  It is never merged with, rebased onto or
# combined with whatever branch happens to be checked out here -- this
# container is only a relay and the current branch is irrelevant to the
# result.  To make that true by construction the script never looks at,
# checks out, resets, cleans, stashes or deletes anything in /TopStor, /pace
# or /topstorweb.  Every project is copied through its own throwaway bare
# repository.
#
# The three projects legitimately hold DIFFERENT commits for the same branch
# name -- they are different repositories with different content.  What is
# guaranteed is that within a project the commit on github is byte for byte
# the commit on abdopuppet.  Every project is proved after the push with a
# fresh ls-remote, and the table at the end prints both sides.
#
# Per project:
#   1. ask abdopuppet and github what commit the branch is at.  If they already
#      agree, that project is skipped and nothing is downloaded.
#   2. otherwise fetch just that one branch, shallowly, into a scratch repo
#   3. push that ref straight across to github
#   4. if github rejects the shallow push, deepen the history and retry once
#   5. ask github what it has now, so the result is proven and not assumed
#
# The github side is always the MoatazNegm account.  The per developer
# repositories in this container also carry a 'remote' pointing at that
# developer's own fork; this script never touches those, which is what stops
# a copy meant for upstream landing in somebody's fork.
#
# overrides (environment):
#   PROXY_BRANCH      branch to copy, if not given on the command line
#   PROXY_PROJECTS    space separated project names
#   PROXY_ABDOPUPET   host holding the bare repositories
#   PROXY_GITHUB      github account / organisation
#   PROXY_DRYRUN      1 = report what would happen, never push
#   PROXY_WORKROOT    where the scratch repositories are made
# ---------------------------------------------------------------------------

PROJECTS=${PROXY_PROJECTS:-"TopStordev HC TopStorweb"}
ABDOPUPET=${PROXY_ABDOPUPET:-10.11.11.252}
GITHUB_USER=${PROXY_GITHUB:-MoatazNegm}
DRYRUN=${PROXY_DRYRUN:-0}
WORKROOT=${PROXY_WORKROOT:-/tmp/proxyrelay}

branch=$1
[ -n "$branch" ] || branch=$PROXY_BRANCH

if [ -z "$branch" ]; then
	echo "usage: proxypush.sh <branch>" >&2
	echo "  copies that branch of every project from $ABDOPUPET out to github," >&2
	echo "  exactly as it is, without merging with anything local" >&2
	exit 1
fi

# abdopuppet answers on two url forms depending on which repository copy asks
pick_abdopuppet() {
	project=$1
	for u in "git://$ABDOPUPET/$1.git" "http://$ABDOPUPET/git/$1.git"; do
		sha=`timeout 60 git ls-remote --heads "$u" "$branch" 2>/dev/null | awk 'NR==1 { print $1 }'`
		if [ -n "$sha" ]; then
			SRC_URL=$u
			SRC_SHA=$sha
			return 0
		fi
	done
	SRC_URL=
	SRC_SHA=
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

# Scratch repositories from an interrupted run are ~75 MB each and are pure
# litter.  Clear them before starting so /tmp does not quietly fill up.
if [ -d "$WORKROOT" ]; then
	stale=`ls -1 "$WORKROOT" 2>/dev/null | wc -l`
	if [ "$stale" -gt 0 ]; then
		echo "clearing $stale leftover scratch director$([ "$stale" -eq 1 ] && echo y || echo ies) in $WORKROOT"
		rm -rf "$WORKROOT"/* 2>/dev/null
	fi
fi
mkdir -p "$WORKROOT"

sumfile=/tmp/proxypush.summary.$$
: > "$sumfile"

note() {
	printf '  %-11s %-16s %-42s %s\n' "$1" "$2" "$3" "$4" >> "$sumfile"
}

for project in $PROJECTS; do
	to_url="https://github.com/$GITHUB_USER/$project.git"

	echo
	echo '###########################################'
	echo "  $project"

	# ---- 1. what is where, without moving any objects ----
	if ! pick_abdopuppet "$project"; then
		echo "  abdopuppet has no branch '$branch' - nothing to copy"
		note "$project" "$branch" "-" "not on abdopuppet"
		missing=`expr $missing + 1`
		continue
	fi
	from_url=$SRC_URL
	src_sha=$SRC_SHA

	dst_sha=`timeout 60 git ls-remote --heads "$to_url" "$branch" 2>/dev/null | awk 'NR==1 { print $1 }'`

	echo "  from : $from_url"
	echo "  to   : $to_url"
	echo "  abdopuppet : $src_sha"
	if [ -z "$dst_sha" ]; then
		echo "  github     : (no such branch yet)"
	elif [ "$dst_sha" = "$src_sha" ]; then
		echo "  github     : $dst_sha"
		echo "  already identical - nothing to do for this project"
		note "$project" "$branch" "$src_sha" "already the same commit"
		skipped=`expr $skipped + 1`
		continue
	else
		echo "  github     : $dst_sha  (different - it will be replaced by $src_sha)"
	fi

	if [ "$DRYRUN" = 1 ]; then
		echo "  PROXY_DRYRUN=1 - would push $src_sha, not pushing"
		note "$project" "$branch" "$src_sha" "DRYRUN, github still $dst_sha"
		continue
	fi

	# ---- a throwaway bare repo, private to this run ----
	scratch="$WORKROOT/$project.$$"
	rm -rf "$scratch"
	mkdir -p "$scratch" || { failed=`expr $failed + 1`; note "$project" "$branch" "$src_sha" "could not create scratch repo"; continue; }
	git init -q --bare "$scratch/relay.git" || {
		echo "  could not create a scratch repository"
		failed=`expr $failed + 1`
		note "$project" "$branch" "$src_sha" "could not create scratch repo"
		rm -rf "$scratch"
		continue
	}
	cd "$scratch/relay.git" || { failed=`expr $failed + 1`; note "$project" "$branch" "$src_sha" "could not enter scratch repo"; continue; }
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
			note "$project" "$branch" "$src_sha" "FETCH FAILED"
			cd /; rm -rf "$scratch"
			continue
		fi
	fi
	got=`git rev-parse "refs/heads/$branch" 2>/dev/null`
	if [ "$got" != "$src_sha" ]; then
		echo "  FAILED: fetched $got but abdopuppet said $src_sha"
		failed=`expr $failed + 1`
		note "$project" "$branch" "$src_sha" "FETCH MISMATCH $got"
		cd /; rm -rf "$scratch"
		continue
	fi
	echo "  have $got locally, exactly as abdopuppet has it"

	# ---- 3. push the ref straight across ----
	biggest=`git ls-tree -r -l "refs/heads/$branch" 2>/dev/null | sort -k4 -nr | head -1 | awk '{printf "%.1f MB  %s", $4/1048576, $5}'`
	echo "  pushing to github -- a big file means a slow upload, this is normal"
	echo "    largest file in the branch : $biggest"

	pushstart=`date +%s`
	pushed=0
	if timeout 600 git push --progress github "$ref" > "$scratch/push" 2>&1; then
		pushsecs=`expr \`date +%s\` - $pushstart`
		echo "  PUSHED $branch to github in ${pushsecs}s"
		pushed=1
	elif timeout 900 git fetch --no-tags --deepen 200 abdopuppet "$ref" > "$scratch/deepen" 2>&1 &&
	     timeout 600 git push --progress github "$ref" > "$scratch/push2" 2>&1; then
		# ---- 4. a shallow pack is refused when github lacks the history ----
		pushsecs=`expr \`date +%s\` - $pushstart`
		echo "  push refused, deepened the history, PUSHED on the second attempt in ${pushsecs}s"
		pushed=1
	else
		echo "  FAILED to push $branch to github"
		[ -f "$scratch/push" ] && sed 's/^/     /' "$scratch/push" | head -6
		[ -f "$scratch/push2" ] && tail -6 "$scratch/push2" | sed 's/^/     /'
		[ -f "$scratch/deepen" ] && tail -4 "$scratch/deepen" | sed 's/^/     /'
		failed=`expr $failed + 1`
	fi

	# ---- 5. prove github really has exactly that commit now ----
	cd /
	now=`timeout 60 git ls-remote --heads "$to_url" "$branch" 2>/dev/null | awk 'NR==1 { print $1 }'`
	if [ "$now" = "$src_sha" ]; then
		echo "  verified: github now has $now"
		if [ "$pushed" -eq 1 ]; then
			ok=`expr $ok + 1`
			note "$project" "$branch" "$src_sha" "PUSHED, github has the same commit"
		else
			note "$project" "$branch" "$src_sha" "already the same commit"
		fi
	elif [ "$pushed" -eq 1 ]; then
		# the push claimed success but the far side disagrees -- that is a
		# real problem and must be counted, not shrugged off
		echo "  *** github reports '$now', expected $src_sha"
		failed=`expr $failed + 1`
		note "$project" "$branch" "$src_sha" "*** MISMATCH, github has ${now:-nothing}"
	else
		note "$project" "$branch" "$src_sha" "PUSH FAILED, github has ${now:-nothing}"
	fi
	rm -rf "$scratch"
done

echo
echo '###########################################'
echo "  branch $branch"
echo "  pushed to github   : $ok"
echo "  already identical  : $skipped"
[ "$missing" -gt 0 ] && echo "  not on abdopuppet  : $missing"
[ "$failed" -gt 0 ] && echo "  failed             : $failed"
echo ""
echo "  commits -- abdopuppet is the source, github must end up identical"
echo "  --------------------------------------------------------"
cat "$sumfile"
echo "  --------------------------------------------------------"
echo "  (the three projects hold different commits for the same branch name:"
echo "   they are separate repositories.  What matters is that the right column"
echo "   shows github holding exactly what the left column names.)"
rm -f "$sumfile"

echo
if [ "$failed" -gt 0 ]; then
	echo "  finished, with errors"
	exit 1
fi
echo "  finished"
exit 0
