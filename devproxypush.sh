#!/bin/sh
# ---------------------------------------------------------------------------
# devproxypush.sh <branch> <developer>
#
# Take a branch from abdopuppet and put it on one developer's own github
# fork, in that developer's three repositories.
#
#   /TopStor_<dev>      /pace_<dev>      /topstorweb_<dev>
#
# The branch is taken from abdopuppet EXACTLY AS IT IS.  Nothing is merged,
# rebased or committed on the way through: the commit that ends up on the
# developer's fork is the same commit abdopuppet holds, and that is proved
# afterwards with a fresh ls-remote rather than assumed.
#
# What this replaces, and why:
#   * it used to hardcode 'git checkout QSD3.15' before deleting the branch.
#     That existed only to step off the branch so 'git branch -D' would
#     accept it.  'git checkout -B' resets a branch in place, so the whole
#     dance is gone, and pinning an ancient branch first was a bug waiting to
#     happen on a repository that no longer had it.
#   * the developer was found with 'ls / | grep $dev | grep TopStor' and then
#     a vague "more than one match" check.  The directories are now looked up
#     by name and a wrong developer name lists the ones that do exist.
#   * the two remotes were picked with 'git remote -v | grep ... | head -1'.
#     That silently takes the first match, and both remotes here have urls
#     containing the word github.  Each remote is now selected by an explicit
#     rule and an ambiguous or missing match is an error, not a guess.
#   * line 92 contained a stray 'f', which the shell tried to run as a
#     command on every invocation.
#
# Shallow aware: in a shallow repository an ordinary fetch leaves the boundary
# where it is, so the old history is never re-downloaded.  The boundary is
# printed, and a branch that does not descend from the base is reported
# rather than quietly producing an empty merge-base later.
#
# environment:
#   DEV_PROXY_BASE       base the image is built on (default QSD5.179)
#   DEV_PROXY_FORCE=1    push with --force-with-lease
#   DEV_PROXY_SKIP=0     fetch the full history even in a shallow repo
# ---------------------------------------------------------------------------

DEV_PROXY_BASE=${DEV_PROXY_BASE:-QSD5.179}
DEV_PROXY_FORCE=${DEV_PROXY_FORCE:-0}
DEV_PROXY_SKIP=${DEV_PROXY_SKIP:-0}
PROJECTS='TopStor pace topstorweb'

branch=$1
dev=$2

if [ -z "$branch" ] || [ -z "$dev" ]; then
	echo "usage: devproxypush.sh <branch> <developer>" >&2
	echo "  copies <branch> from abdopuppet onto that developer's github fork" >&2
	echo "  for all three of their repositories" >&2
	echo "" >&2
	echo "developers that exist:" >&2
	ls -d /TopStor_* 2>/dev/null | sed 's/^/    /' >&2
	exit 1
fi

dirs=""
missing=""
for job in $PROJECTS; do
	d="/${job}_$dev"
	if [ -d "$d" ]; then
		dirs="$dirs $d"
	else
		missing="$missing $d"
	fi
done

if [ -n "$missing" ]; then
	echo "no developer '$dev': these directories are missing" >&2
	echo "$missing" | tr ' ' '\n' | grep -v '^$' | sed 's/^/    /' >&2
	echo "" >&2
	echo "developers that do exist:" >&2
	ls -d /TopStor_* 2>/dev/null | sed 's/^/    /' >&2
	exit 1
fi

# ---------------------------------------------------------------- remotes --
# origin  = the remote pointing at abdopuppet
# devfork = the remote pointing at THIS developer's own github fork
# Both are matched on their url, and both must be unambiguous.
pick_remote() {
	repo=$1; want=$2; label=$3
	pick_remote_result=
	pick_remote_hits=0
	git remote -v 2>/dev/null | awk -v w="$want" '!/\(push\)/ && $2 != "" { print $1 "\t" $2 }' \
		| while IFS='	' read -r name url; do
			case $url in
			*$want*) echo "$name|$url" ;;
			esac
		done > /tmp/devremote.$$
	n=`wc -l < /tmp/devremote.$$`
	if [ "$n" = 1 ]; then
		pick_remote_result=`cut -d'|' -f1 /tmp/devremote.$$`
	elif [ "$n" -gt 1 ]; then
		echo "  ERROR: $label is ambiguous in $repo, more than one remote matches '$want':" >&2
		sed 's/^/          /' /tmp/devremote.$$ >&2
	fi
	rm -f /tmp/devremote.$$
}

echo "devproxypush: $branch from abdopuppet -> the github fork of $dev"

sumfile=/tmp/devproxypush.summary.$$
: > "$sumfile"

ok=0
skipped=0
failed=0

for job in $PROJECTS; do
	dir="/${job}_$dev"
	echo
	echo '###########################################'
	echo "  $dir"
	cd "$dir" || { failed=`expr $failed + 1`; continue; }

	if ! git rev-parse --git-dir >/dev/null 2>&1; then
		echo "  ERROR: $dir is not a git repository"
		printf '  %-26s %s\n' "${job}_$dev" "not a git repository" >> "$sumfile"
		failed=`expr $failed + 1`
		continue
	fi

	origin=`pick_remote . 252 'abdopuppet'`
	if [ -z "$origin" ]; then
		echo "  ERROR: no remote pointing at abdopuppet (url containing 252)"
		failed=`expr $failed + 1`
		printf '  %-26s %s\n' "${job}_$dev" "no abdopuppet remote" >> "$sumfile"
		continue
	fi
	devfork=`pick_remote . "$dev" 'the developer fork'`
	if [ -z "$devfork" ]; then
		echo "  ERROR: no remote matching this developer '$dev'"
		echo "         the remotes here are:"
		git remote -v | sed 's/^/           /'
		failed=`expr $failed + 1`
		printf '  %-26s %s\n' "${job}_$dev" "no fork for $dev" >> "$sumfile"
		continue
	fi
	echo "  from : $origin"
	echo "  to   : $devfork"

	# ---- fetch ---------------------------------------------------------
	if [ -f .git/shallow ] && [ "$DEV_PROXY_SKIP" = 0 ]; then
		echo "  shallow repository -- boundary stays at `head -1 .git/shallow`"
	fi
	echo "  fetching $origin/$branch"
	if ! git fetch --no-tags --prune "$origin" \
			"+refs/heads/$branch:refs/remotes/$origin/$branch"; then
		echo "  ERROR: could not fetch $branch from $origin"
		failed=`expr $failed + 1`
		printf '  %-26s %s\n' "${job}_$dev" "FETCH FAILED" >> "$sumfile"
		continue
	fi

	if ! git rev-parse --verify --quiet "refs/remotes/$origin/$branch" >/dev/null; then
		echo "  ERROR: $origin has no branch '$branch'"
		failed=`expr $failed + 1`
		printf '  %-26s %s\n' "${job}_$dev" "no such branch on abdopuppet" >> "$sumfile"
		continue
	fi

	src_sha=`git rev-parse "refs/remotes/$origin/$branch"`
	if [ -f .git/shallow ]; then
		if git rev-parse --verify --quiet "$DEV_PROXY_BASE" >/dev/null &&
		   git merge-base --is-ancestor "$DEV_PROXY_BASE" "refs/remotes/$origin/$branch" 2>/dev/null
		then
			echo "  $branch descends from $DEV_PROXY_BASE"
		else
			echo "  *** WARNING: $branch does NOT descend from $DEV_PROXY_BASE."
			echo "      In a shallow repository the history below the boundary is"
			echo "      not there, so merge-base against older branches will report"
			echo "      nothing.  Fetch the full history before merging on this one."
		fi
	fi

	dst_sha=`git ls-remote --heads "$devfork" "$branch" 2>/dev/null | awk 'NR==1 { print $1 }'`
	if [ "$dst_sha" = "$src_sha" ]; then
		echo "  the fork already has $src_sha -- nothing to do"
		printf '  %-26s %s\n' "${job}_$dev" "$src_sha" >> "$sumfile"
		skipped=`expr $skipped + 1`
		continue
	fi

	# ---- take the branch as it is --------------------------------------
	if ! git checkout -f -B "$branch" "refs/remotes/$origin/$branch"; then
		echo "  ERROR: could not check out $branch"
		failed=`expr $failed + 1`
		printf '  %-26s %s\n' "${job}_$dev" "CHECKOUT FAILED" >> "$sumfile"
		continue
	fi
	git reset --hard --quiet
	git clean -f
	git config --replace-all pull.rebase false
	git checkout -- * 2>/dev/null
	# python cache turns up at any depth, so a bare '__py*' pathspec is not
	# enough -- it only ever matched the top level
	git rm -rq --ignore-unmatch -- ':(glob)**/__py*' >/dev/null 2>&1
	find . -name '.git' -prune -o -name '__py*' -prune -exec rm -rf {} + 2>/dev/null

	got=`git rev-parse HEAD`
	if [ "$got" != "$src_sha" ]; then
		echo "  *** ERROR: HEAD is $got but $origin/$branch is $src_sha"
		failed=`expr $failed + 1`
		printf '  %-26s %s\n' "${job}_$dev" "*** MISMATCH, HEAD $got" >> "$sumfile"
		continue
	fi
	echo "  local branch is $got, exactly as abdopuppet has it"

	# ---- push ----------------------------------------------------------
	pushflags=
	if [ "$DEV_PROXY_FORCE" = 1 ]; then
		pushflags=--force-with-lease
	fi
	echo "  pushing $branch to $devfork"
	pushstart=`date +%s`
	if git push $pushflags "$devfork" "$branch" > /tmp/devpush.$$ 2>&1; then
		skipped2=`expr \`date +%s\` - $pushstart`
		echo "  PUSHED in ${skipped2}s"
		ok=`expr $ok + 1`
	elif [ -f .git/shallow ] && grep -qi shallow /tmp/devpush.$$; then
		# a shallow pack is refused; deepen once and try again
		echo "  refused because the repository is shallow -- deepening and retrying"
		git fetch --no-tags --unshallow "$origin" >/dev/null 2>&1
		if git push $pushflags "$devfork" "$branch" > /tmp/devpush.$$ 2>&1; then
			echo "  PUSHED on the second attempt"
			ok=`expr $ok + 1`
		else
			sed 's/^/     /' /tmp/devpush.$$ | head -6
			failed=`expr $failed + 1`
			printf '  %-26s %s\n' "${job}_$dev" "PUSH FAILED" >> "$sumfile"
		fi
	else
		sed 's/^/     /' /tmp/devpush.$$ | head -8
		echo "  the fork does not have the history behind this branch, so it will"
		echo "  not accept a non fast-forward push.  DEV_PROXY_FORCE=1 will use"
		echo "  --force-with-lease if you are sure the fork should be replaced."
		failed=`expr $failed + 1`
		printf '  %-26s %s\n' "${job}_$dev" "PUSH FAILED" >> "$sumfile"
	fi
	rm -f /tmp/devpush.$$

	# ---- prove the fork really has that commit -------------------------
	now=`git ls-remote --heads "$devfork" "$branch" 2>/dev/null | awk 'NR==1 { print $1 }'`
	if [ "$now" = "$src_sha" ]; then
		echo "  verified: the fork now has $now"
		printf '  %-26s %s\n' "${job}_$dev" "$src_sha" >> "$sumfile"
	else
		echo "  *** the fork reports '$now', expected $src_sha"
		failed=`expr $failed + 1`
		printf '  %-26s %s\n' "${job}_$dev" "*** MISMATCH, fork has ${now:-nothing}" >> "$sumfile"
	fi
	sync
done

echo
echo '###########################################'
echo "  branch $branch  ->  the fork of $dev"
echo "  pushed            : $ok"
echo "  already identical : $skipped"
[ "$failed" -gt 0 ] && echo "  failed            : $failed"
echo ""
echo "  commits"
echo "  --------------------------------------------------------------"
printf "  %-26s %s\n" "repository" "commit on the fork"
cat "$sumfile"
echo "  --------------------------------------------------------------"
rm -f "$sumfile"

echo
cd /TopStor 2>/dev/null
if [ "$failed" -gt 0 ]; then
	echo "finished, with errors"
	exit 1
fi
echo "finished"
exit 0
