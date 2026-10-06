#!/bin/sh
# ---------------------------------------------------------------------------
# proxyupdate.sh <branch>
#
# Copy one branch of all three projects from github back out to abdopuppet.
# This is the mirror image of proxypush.sh.
#
# The branch is taken from github EXACTLY AS IT IS, and abdopuppet ends up
# holding the identical commit.  It is never merged with, rebased onto or
# combined with whatever branch happens to be checked out in this container --
# the current branch is irrelevant to the result.  To make that true by
# construction the script never looks at, checks out, resets, cleans, stashes
# or deletes anything in /TopStor, /pace or /topstorweb.  Every project is
# copied through its own throwaway bare repository.
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

PROJECTS=${PROXY_PROJECTS:-"TopStordev HC TopStorweb"}
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

echo "  proxyupdate: github user $GITHUB_USER -> abdopuppet $ABDOPUPET (url forms: ${PROXY_ABD_FORMS:-git://%h/%r.git http://%h/git/%r.git}), branch $branch"

# ---- verbosity helpers: nothing here may stay silent for more than ~10 seconds ----
# git must never wait for a username/password on a terminal that is not there: that looks exactly like a hang
GIT_TERMINAL_PROMPT=0
export GIT_TERMINAL_PROMPT

# lsremote <url>: sha of $branch at that url on stdout; what it is doing, how long it took and
# why it failed go to stderr (so they show on the screen but do not end up in the sha)
lsremote() {
	_t0=`date +%s`
	_err=/tmp/proxyupdate.lsr.$$
	echo "  asking $1 for $branch (max 60s) ..." >&2
	_out=`timeout 60 git ls-remote --heads "$1" "$branch" 2>"$_err"`
	_rc=$?
	_secs=`expr \`date +%s\` - $_t0`
	if [ "$_rc" -eq 124 ]; then
		echo "    TIMED OUT after 60s -- $1 is not answering (network? dns? credentials?)" >&2
	elif [ "$_rc" -ne 0 ]; then
		echo "    FAILED (exit $_rc) after ${_secs}s: `head -2 "$_err" | tr '\n' ' '`" >&2
	elif [ -z "$_out" ]; then
		echo "    answered in ${_secs}s: no such branch there" >&2
	else
		echo "    answered in ${_secs}s" >&2
	fi
	rm -f "$_err"
	echo "$_out" | awk 'NR==1 { print $1 }'
}

# runv <label> <max seconds> <logfile> <command...>: run a long command, keep its output in the
# logfile, and every 10 seconds say that it is still running, for how long and what git last said
# (git's progress line: objects, MB, speed).  Returns the command's exit status (124 = timed out).
runv() {
	_label=$1; _max=$2; _log=$3
	shift 3
	_t0=`date +%s`
	echo "  [`date +%H:%M:%S`] $_label (max ${_max}s) ..."
	timeout "$_max" "$@" > "$_log" 2>&1 &
	_pid=$!
	_n=0
	while kill -0 "$_pid" 2>/dev/null; do
		sleep 1
		_n=`expr $_n + 1`
		if [ `expr $_n % 10` -eq 0 ]; then
			_last=`tr '\r' '\n' < "$_log" 2>/dev/null | grep -v '^$' | tail -1 | cut -c1-110`
			echo "    ... $_label: still running, ${_n}s so far ${_last:+-- $_last}"
		fi
	done
	wait "$_pid"
	_rc=$?
	_secs=`expr \`date +%s\` - $_t0`
	if [ "$_rc" -eq 124 ]; then
		echo "    $_label: TIMED OUT after ${_max}s"
	elif [ "$_rc" -eq 0 ]; then
		echo "    $_label: done in ${_secs}s"
	else
		echo "    $_label: exit $_rc after ${_secs}s"
	fi
	return $_rc
}

# github needs a working resolver
if [ -w /etc/resolv.conf ]; then
	echo 'nameserver 8.8.8.8' > /etc/resolv.conf 2>/dev/null
fi

# deepen_for_push <source remote> <destination url> <ref> <scratch dir>
# A shallow push is refused ("shallow update not allowed") unless EVERY commit at the shallow boundary is
# already in the destination.  A branch with merge commits has several boundary commits (one per line of
# history), so one known boundary is not enough.  Deepening by 200 commits in one go downloads hundreds of MB
# (TopStor: ~800 MB-1.3 GB), so: deepen ONE commit at a time and
#   - stop when all boundary commits are tips of the destination's refs (the push is then certain), or
#   - once at least one of them is (the main line has arrived), try the push after every step: the other
#     lines may end on commits the destination has but that are not branch tips, and only a push can tell.
# Only if nothing is accepted within PROXY_MAXDEEP commits (default 60) fall back to the big deepen, loudly.
# Returns 0 when the history is deep enough (the caller's push then succeeds, or is already done).
deepen_for_push() {
	_src=$1; _dst=$2; _ref=$3; _sc=$4
	_gd=`git rev-parse --git-dir`
	echo "  [`date +%H:%M:%S`] asking $_dst which commits it already has ..."
	_tips=`timeout 120 git ls-remote "$_dst" 2>/dev/null | awk '{print $1}'`
	echo "    it has $(echo "$_tips" | grep -c .) refs"
	_n=0
	while :; do
		_known=0; _unknown=0
		for _r in `cat "$_gd/shallow" 2>/dev/null`; do
			if echo "$_tips" | grep -qx "$_r"; then _known=`expr $_known + 1`; else _unknown=`expr $_unknown + 1`; fi
		done
		if [ "$_unknown" -eq 0 ]; then
			echo "    all $_known boundary commit(s) are known to the destination after $_n extra commit(s) -- small push"
			return 0
		fi
		if [ "$_known" -gt 0 ]; then
			echo "    $_known boundary commit(s) known, $_unknown other(s) not a branch tip there -- trying the push"
			if timeout 600 git push "$_dst" "$_ref" > "$_sc/trypush" 2>&1; then
				echo "    accepted after $_n extra commit(s)"
				return 0
			fi
			grep -q "shallow update not allowed" "$_sc/trypush" || { echo "    push failed for another reason:"; tail -3 "$_sc/trypush" | sed 's/^/       /'; return 1; }
		fi
		[ "$_n" -ge "${PROXY_MAXDEEP:-60}" ] && break
		_n=`expr $_n + 1`
		if ! timeout 300 git fetch -q --no-tags --deepen 1 "$_src" "$_ref" > "$_sc/deepen" 2>&1; then
			echo "    deepening by one commit failed:"; tail -3 "$_sc/deepen" | sed 's/^/       /'
			return 1
		fi
		echo "    deepened by one commit ($_n) -- `wc -l < "$_gd/shallow" 2>/dev/null || echo 0` boundary commit(s) now"
	done
	echo "    *** not accepted within $_n extra commits (the destination has no usable history of this branch)."
	echo "    *** falling back to a deepen of ${PROXY_FALLBACK_DEEPEN:-200} commits: this can be a LARGE download (up to ~1.3 GB for TopStor)"
	runv "deepening by ${PROXY_FALLBACK_DEEPEN:-200} commits" 900 "$_sc/deepen" git fetch --progress --no-tags --deepen "${PROXY_FALLBACK_DEEPEN:-200}" "$_src" "$_ref"
}

# abdopuppet is a git-daemon (git://<ip>/<repo>.git, port 9418, receive-pack enabled -- the form it serves itself);
# a physical node's software container serves the same repos over http (http://<ip>/git/<repo>.git).
# %h = the host, %r = the repository.  PROXY_ABD_FORMS changes the list (e.g. to add an ssh:// form).
ABD_FORMS=${PROXY_ABD_FORMS:-"git://%h/%r.git http://%h/git/%r.git"}

# pick_abdopuppet <repo>: the first URL form that ANSWERS at all (the branch does not have to exist there yet).
# Sets ABD_URL and ABD_SHA (the branch's commit there, empty when it is not there).  Returns 1 and says why when
# no form answers -- that is a connectivity problem, not a missing branch.
pick_abdopuppet() {
	ABD_URL=
	ABD_SHA=
	# the web repo is TopStorweb.git since 2026-10-06 (TopStorWeb.git is a symlink to it); an abdopuppet that
	# was not migrated only has the old spelling, so try both
	case $1 in
	TopStorweb) _names="TopStorweb TopStorWeb" ;;
	TopStorWeb) _names="TopStorWeb TopStorweb" ;;
	*)          _names=$1 ;;
	esac
	for _n in $_names; do
	for _f in $ABD_FORMS; do
		_u=`echo "$_f" | sed "s|%h|$ABDOPUPET|; s|%r|$_n|"`
		_err=/tmp/proxy.pick.$$
		_t0=`date +%s`
		echo "  asking $_u (max 60s) ..." >&2
		_all=`timeout 60 git ls-remote --heads "$_u" 2>"$_err"`
		_rc=$?
		_secs=`expr \`date +%s\` - $_t0`
		if [ "$_rc" -eq 0 ]; then
			ABD_URL=$_u
			ABD_SHA=`echo "$_all" | awk -v b="refs/heads/$branch" '$2 == b { print $1 }'`
			echo "    answered in ${_secs}s, `echo "$_all" | grep -c .` branches, $branch there: ${ABD_SHA:-no}" >&2
			rm -f "$_err"
			return 0
		elif [ "$_rc" -eq 124 ]; then
			echo "    TIMED OUT after 60s" >&2
		else
			echo "    no (exit $_rc): `head -2 "$_err" | tr '\n' ' '`" >&2
		fi
	done
	done
	rm -f "$_err"
	echo "  *** $ABDOPUPET does not answer for repository $1 on any of: $ABD_FORMS" >&2
	echo "      git:// needs tcp 9418 open to it, http:// needs port 80.  Check PROXY_ABDOPUPET (now $ABDOPUPET) or set PROXY_ABD_FORMS." >&2
	return 1
}

# bridge: topstorweb must have QSD5.211 as a branch (`git branch`, not a look at any remote), because
# systempull.sh pulls it first on a node that does not have it.  If it is not listed, relay it from
# github to abdopuppet first (topstorweb only), then pull it from abdopuppet into the local repo.
BRIDGE=${PROXY_BRIDGE:-QSD5.211}
BRIDGE_DIR=${PROXY_BRIDGE_DIR:-/topstorweb}
if [ "$branch" != "$BRIDGE" ] && [ -z "$PROXY_NO_BRIDGE" ] && [ -d "$BRIDGE_DIR/.git" ] &&
   [ -z "`git -C "$BRIDGE_DIR" branch --list "$BRIDGE" 2>/dev/null`" ]; then
	echo "  $BRIDGE is not a branch of $BRIDGE_DIR -- relaying it first, then $branch"
	PROXY_NO_BRIDGE=1 PROXY_PROJECTS=TopStorweb sh "$0" "$BRIDGE"
	# ... and pull it into $BRIDGE_DIR as a local branch (a fetch into a branch that is not checked out:
	# no checkout, no reset) from whichever abdopuppet URL form answers, so that `git branch` lists it
	echo "  pulling $BRIDGE into $BRIDGE_DIR from $ABDOPUPET ..."
	_keep=$branch; branch=$BRIDGE
	if [ "$DRYRUN" = 1 ]; then
		echo "  PROXY_DRYRUN=1 - not pulling it"
	elif ! pick_abdopuppet TopStorweb; then
		echo "  *** abdopuppet is not reachable -- $BRIDGE not pulled into $BRIDGE_DIR"
	elif timeout 600 git -C "$BRIDGE_DIR" fetch --progress --no-tags "$ABD_URL" "+refs/heads/$BRIDGE:refs/heads/$BRIDGE"; then
		echo "  $BRIDGE is now a branch of $BRIDGE_DIR: `git -C "$BRIDGE_DIR" rev-parse --short "refs/heads/$BRIDGE"`"
	else
		echo "  *** could not pull $BRIDGE into $BRIDGE_DIR from $ABD_URL (is it checked out there?) -- continuing"
	fi
	branch=$_keep
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

sumfile=/tmp/proxyupdate.summary.$$
: > "$sumfile"

note() {
	printf '  %-11s %-16s %-42s %s\n' "$1" "$2" "$3" "$4" >> "$sumfile"
}

for project in $PROJECTS; do
	echo
	echo '###########################################'
	echo "  $project"

	# ---- 1. what is where, without moving any objects ----
	from_url="https://github.com/$GITHUB_USER/$project.git"
	echo "  [`date +%H:%M:%S`] checking what is where"
	src_sha=`lsremote "$from_url"`
	if [ -z "$src_sha" ]; then
		echo "  github has no branch '$branch' for $GITHUB_USER/$project - nothing to copy"
		note "$project" "$branch" "-" "not on github"
		missing=`expr $missing + 1`
		continue
	fi

	if pick_abdopuppet "$project"; then
		to_url=$ABD_URL
		dst_sha=$ABD_SHA
	else
		echo "  *** cannot reach abdopuppet for $project -- nothing pushed"
		note "$project" "$branch" "$src_sha" "ABDOPUPPET NOT REACHABLE"
		failed=`expr $failed + 1`
		continue
	fi

	echo "  from : $from_url"
	echo "  to   : $to_url"
	echo "  github     : $src_sha"
	if [ -z "$dst_sha" ]; then
		echo "  $ABDOPUPET : (no such branch yet)"
	elif [ "$dst_sha" = "$src_sha" ]; then
		echo "  $ABDOPUPET : $dst_sha"
		echo "  already identical - nothing to do for this project"
		note "$project" "$branch" "$src_sha" "already the same commit"
		skipped=`expr $skipped + 1`
		continue
	else
		echo "  $ABDOPUPET : $dst_sha  (different - it will be replaced by $src_sha)"
	fi

	if [ "$DRYRUN" = 1 ]; then
		echo "  PROXY_DRYRUN=1 - would push $src_sha to $ABDOPUPET, not pushing"
		note "$project" "$branch" "$src_sha" "DRYRUN, abdopuppet still $dst_sha"
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
	git remote add github "$from_url" >/dev/null 2>&1
	git remote add abdopuppet "$to_url" >/dev/null 2>&1

	# ---- 2. shallow fetch of the one branch we need ----
	ref="+refs/heads/$branch:refs/heads/$branch"
	if ! runv "fetching $branch from github (shallow)" 300 "$scratch/fetch" git fetch --progress --no-tags --depth 1 github "$ref"; then
		tail -3 "$scratch/fetch" | sed 's/^/     /'
		echo "  shallow fetch failed - fetching the full history instead ..."
		if ! runv "fetching $branch from github (full history)" 900 "$scratch/fetch" git fetch --progress --no-tags github "$ref"; then
			echo "  FAILED to fetch $branch from github"
			tail -5 "$scratch/fetch" | sed 's/^/     /'
			failed=`expr $failed + 1`
			note "$project" "$branch" "$src_sha" "FETCH FAILED"
			cd /; rm -rf "$scratch"
			continue
		fi
	fi
	got=`git rev-parse "refs/heads/$branch" 2>/dev/null`
	if [ "$got" != "$src_sha" ]; then
		echo "  FAILED: fetched $got but github said $src_sha"
		failed=`expr $failed + 1`
		note "$project" "$branch" "$src_sha" "FETCH MISMATCH $got"
		cd /; rm -rf "$scratch"
		continue
	fi
	echo "  have $got locally, exactly as github has it"

	# ---- 3. push the ref straight across ----
	biggest=`git ls-tree -r -l "refs/heads/$branch" 2>/dev/null | sort -k4 -nr | head -1 | awk '{printf "%.1f MB  %s", $4/1048576, $5}'`
	echo "  pushing to $ABDOPUPET -- a big file means a slow transfer, this is normal"
	echo "    largest file in the branch : $biggest"

	pushstart=`date +%s`
	pushed=0
	if runv "pushing $branch to $ABDOPUPET" 600 "$scratch/push" git push --progress abdopuppet "$ref"; then
		pushsecs=`expr \`date +%s\` - $pushstart`
		echo "  PUSHED $branch to $ABDOPUPET in ${pushsecs}s"
		pushed=1
	elif { sed 's/^/     /' "$scratch/push" | tail -4
	       echo "  push refused (shallow) -- deepening only as far as $ABDOPUPET needs"
	       deepen_for_push github "$to_url" "$ref" "$scratch"; } &&
	     runv "pushing $branch to $ABDOPUPET (second attempt)" 600 "$scratch/push2" git push --progress abdopuppet "$ref"; then
		# ---- 4. a shallow pack is refused when the far side lacks history ----
		pushsecs=`expr \`date +%s\` - $pushstart`
		echo "  push refused, deepened the history, PUSHED on the second attempt in ${pushsecs}s"
		pushed=1
	else
		echo "  FAILED to push $branch to $ABDOPUPET"
		[ -f "$scratch/push" ] && sed 's/^/     /' "$scratch/push" | head -6
		[ -f "$scratch/push2" ] && tail -6 "$scratch/push2" | sed 's/^/     /'
		[ -f "$scratch/deepen" ] && tail -4 "$scratch/deepen" | sed 's/^/     /'
		failed=`expr $failed + 1`
	fi

	# ---- 5. prove abdopuppet really has exactly that commit now ----
	cd /
	now=`lsremote "$to_url"`
	if [ "$now" = "$src_sha" ]; then
		echo "  verified: $ABDOPUPET now has $now"
		if [ "$pushed" -eq 1 ]; then
			ok=`expr $ok + 1`
			note "$project" "$branch" "$src_sha" "PUSHED, abdopuppet has the same commit"
		else
			note "$project" "$branch" "$src_sha" "already the same commit"
		fi
	elif [ "$pushed" -eq 1 ]; then
		echo "  *** $ABDOPUPET reports '$now', expected $src_sha"
		failed=`expr $failed + 1`
		note "$project" "$branch" "$src_sha" "*** MISMATCH, abdopuppet has ${now:-nothing}"
	else
		note "$project" "$branch" "$src_sha" "PUSH FAILED, abdopuppet has ${now:-nothing}"
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
echo ""
echo "  commits -- github is the source, abdopuppet must end up identical"
echo "  --------------------------------------------------------"
cat "$sumfile"
echo "  --------------------------------------------------------"
echo "  (the three projects hold different commits for the same branch name:"
echo "   they are separate repositories.  What matters is that the right column"
echo "   shows abdopuppet holding exactly what the left column names.)"
rm -f "$sumfile"

echo
if [ "$failed" -gt 0 ]; then
	echo "  finished, with errors"
	exit 1
fi
echo "  finished"
exit 0
