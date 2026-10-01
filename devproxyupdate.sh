#!/usr/bin/sh
# ---------------------------------------------------------------------------
# devproxyupdate.sh <branch> <developer>
#
# Take a branch off the github side and put it back on abdopuppet, in one
# developer's three repositories.
#
#   /TopStor_<dev>      /pace_<dev>      /topstorweb_<dev>
#
# The branch is taken from github EXACTLY AS IT IS.  Nothing is merged,
# rebased or committed on the way through: the commit that lands on
# abdopuppet is the same commit github holds, and that is proved afterwards
# with a fresh ls-remote rather than assumed.
#
# Which github side?  Always the upstream account, DEV_PROXY_GITHUB, which
# defaults to MoatazNegm.  These repositories also carry a remote pointing at
# the developer's own fork, and the old script matched remotes with
# 'git remote -v | grep github | grep  QuickStor' -- two spaces and all.  Both
# of those remotes have a url containing the word github, so the choice was
# down to whichever line came first.  Naming the account outright means a
# copy meant for abdopuppet can never land in somebody's fork by accident.
#
# What this replaces, and why:
#   * the tempb parking branch, the delete-then-recreate dance and the
#     duplicated block of worktree clean-ups are all gone.  tempb only ever
#     existed to step off the branch so 'git branch -D' would accept it;
#     'git checkout -B' resets a branch in place and needs none of it.
#   * the developer was found with 'ls / | grep $dev | grep TopStor' and a
#     vague "more than one match" check.  The directories are now looked up by
#     name, and a wrong developer name lists the ones that do exist.
#   * each remote is selected by an explicit rule, and an ambiguous or missing
#     match is an error rather than a silent guess at head -1.
#
# Shallow aware: in a shallow repository an ordinary fetch leaves the boundary
# where it is, so the old history is never re-downloaded.  The boundary is
# printed, and a branch that does not descend from the base is reported
# rather than quietly producing an empty merge-base later.
#
# environment:
#   DEV_PROXY_BASE       base the image is built on (default QSD5.179)
#   DEV_PROXY_GITHUB     upstream github account (default MoatazNegm)
#   DEV_PROXY_FORCE=1    push with --force-with-lease
#   DEV_PROXY_SKIP=0     fetch the full history even in a shallow repo
# ---------------------------------------------------------------------------

DEV_PROXY_BASE=${DEV_PROXY_BASE:-QSD5.179}
DEV_PROXY_GITHUB=${DEV_PROXY_GITHUB:-MoatazNegm}
DEV_PROXY_FORCE=${DEV_PROXY_FORCE:-0}
DEV_PROXY_SKIP=${DEV_PROXY_SKIP:-0}
PROJECTS='TopStor pace topstorweb'

branch=$1
dev=$2

if [ -z "$branch" ] || [ -z "$dev" ]; then
	echo "usage: devproxyupdate.sh <branch> <developer>" >&2
	echo "  copies <branch> from github ($DEV_PROXY_GITHUB) onto abdopuppet" >&2
	echo "  for that developer's three repositories" >&2
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

# github needs a working resolver
if [ -w /etc/resolv.conf ]; then
	echo 'nameserver 8.8.8.8' > /etc/resolv.conf 2>/dev/null
fi

# pick_remote <url fragment> <label> -> the single remote whose url matches
pick_remote() {
	want=$1; label=$2
	git remote -v 2>/dev/null | awk '!/\(push\)/ && $2 != "" { print $1 "\t" $2 }' \
		| while IFS='	' read -r name url; do
			case $url in
			*$want*) echo "$name|$url" ;;
			esac
		done > /tmp/devremote.$$
	n=`wc -l < /tmp/devremote.$$`
	if [ "$n" = 1 ]; then
		cut -d'|' -f1 /tmp/devremote.$$
	elif [ "$n" -gt 1 ]; then
		echo "  ERROR: $label is ambiguous, more than one remote matches '$want':" >&2
		sed 's/^/          /' /tmp/devremote.$$ >&2
	fi
	rm -f /tmp/devremote.$$
}

echo "devproxyupdate: $branch from github ($DEV_PROXY_GITHUB) -> abdopuppet, for $dev"

sumfile=/tmp/devproxyupdate.summary.$$
: > "$sumfile"

ok=0
skipped=0
missingb=0
failed=0

for job in $PROJECTS; do
	dir="/${job}_$dev"
	echo
	echo '###########################################'
	echo "  $dir"
	cd "$dir" || { failed=`expr $failed + 1`; continue; }

	if ! git rev-parse --git-dir >/dev/null 2>&1; then
		echo "  ERROR: $dir is not a git repository"
		printf '  %-26s %s\n' "$job_$dev" "not a git repository" >> "$sumfile"
		failed=`expr $failed + 1`
		continue
	fi

	gh=`pick_remote "$DEV_PROXY_GITHUB" 'github'`
	if [ -z "$gh" ]; then
		echo "  ERROR: no remote pointing at github ($DEV_PROXY_GITHUB)"
		git remote -v | sed 's/^/           /'
		failed=`expr $failed + 1`
		printf '  %-26s %s\n' "$job_$dev" "no github remote" >> "$sumfile"
		continue
	fi
	origin=`pick_remote 252 'abdopuppet'`
	if [ -z "$origin" ]; then
		echo "  ERROR: no remote pointing at abdopuppet (url containing 252)"
		failed=`expr $failed + 1`
		printf '  %-26s %s\n' "$job_$dev" "no abdopuppet remote" >> "$sumfile"
		continue
	fi
	echo "  from : $gh"
	echo "  to   : $origin"

	# ---- fetch ---------------------------------------------------------
	if [ -f .git/shallow ] && [ "$DEV_PROXY_SKIP" = 0 ]; then
		echo "  shallow repository -- boundary stays at `head -1 .git/shallow`"
	fi
	echo "  fetching $gh/$branch"
	if ! git fetch --no-tags --prune "$gh" \
			"+refs/heads/$branch:refs/remotes/$gh/$branch"; then
		echo "  ERROR: could not fetch $branch from $gh"
		failed=`expr $failed + 1`
		printf '  %-26s %s\n' "$job_$dev" "FETCH FAILED" >> "$sumfile"
		continue
	fi

	if ! git rev-parse --verify --quiet "refs/remotes/$gh/$branch" >/dev/null; then
		echo "  ERROR: $gh has no branch '$branch'"
		missingb=`expr $missingb + 1`
		printf '  %-26s %s\n' "$job_$dev" "no such branch on github" >> "$sumfile"
		continue
	fi

	src_sha=`git rev-parse "refs/remotes/$gh/$branch"`
	if [ -f .git/shallow ]; then
		if git rev-parse --verify --quiet "$DEV_PROXY_BASE" >/dev/null &&
		   git merge-base --is-ancestor "$DEV_PROXY_BASE" "refs/remotes/$gh/$branch" 2>/dev/null
		then
			echo "  $branch descends from $DEV_PROXY_BASE"
		else
			echo "  *** WARNING: $branch does NOT descend from $DEV_PROXY_BASE."
			echo "      In a shallow repository the history below the boundary is"
			echo "      not there, so merge-base against older branches will report"
			echo "      nothing.  Fetch the full history before merging on this one."
		fi
	fi

	dst_sha=`git ls-remote --heads "$origin" "$branch" 2>/dev/null | awk 'NR==1 { print $1 }'`
	if [ "$dst_sha" = "$src_sha" ]; then
		echo "  abdopuppet already has $src_sha -- nothing to do"
		printf '  %-26s %s\n' "$job_$dev" "$src_sha" >> "$sumfile"
		skipped=`expr $skipped + 1`
		continue
	fi

	# ---- take the branch as it is --------------------------------------
	if ! git checkout -f -B "$branch" "refs/remotes/$gh/$branch"; then
		echo "  ERROR: could not check out $branch"
		failed=`expr $failed + 1`
		printf '  %-26s %s\n' "$job_$dev" "CHECKOUT FAILED" >> "$sumfile"
		continue
	fi
	git reset --hard --quiet
	git clean -f
	git config --replace-all pull.rebase false
	git checkout -- * 2>/dev/null
	git rm -rq --ignore-unmatch -- ':(glob)**/__py*' >/dev/null 2>&1
	find . -name '.git' -prune -o -name '__py*' -prune -exec rm -rf {} + 2>/dev/null

	got=`git rev-parse HEAD`
	if [ "$got" != "$src_sha" ]; then
		echo "  *** ERROR: HEAD is $got but $gh/$branch is $src_sha"
		failed=`expr $failed + 1`
		printf '  %-26s %s\n' "$job_$dev" "*** MISMATCH, HEAD $got" >> "$sumfile"
		continue
	fi
	echo "  local branch is $got, exactly as github has it"

	# ---- push ----------------------------------------------------------
	pushflags=
	if [ "$DEV_PROXY_FORCE" = 1 ]; then
		pushflags=--force-with-lease
	fi
	echo "  pushing $branch to $origin"
	pushstart=`date +%s`
	if git push $pushflags "$origin" "$branch" > /tmp/devpush.$$ 2>&1; then
		taken=`expr \`date +%s\` - $pushstart`
		echo "  PUSHED in ${taken}s"
		ok=`expr $ok + 1`
	elif [ -f .git/shallow ] && grep -qi shallow /tmp/devpush.$$; then
		echo "  refused because the repository is shallow -- deepening and retrying"
		git fetch --no-tags --unshallow "$gh" >/dev/null 2>&1
		if git push $pushflags "$origin" "$branch" > /tmp/devpush.$$ 2>&1; then
			echo "  PUSHED on the second attempt"
			ok=`expr $ok + 1`
		else
			sed 's/^/     /' /tmp/devpush.$$ | head -6
			failed=`expr $failed + 1`
			printf '  %-26s %s\n' "$job_$dev" "PUSH FAILED" >> "$sumfile"
		fi
	else
		sed 's/^/     /' /tmp/devpush.$$ | head -8
		echo "  abdopuppet does not have the history behind this branch, so it"
		echo "  will not accept a non fast-forward push.  DEV_PROXY_FORCE=1 will"
		echo "  use --force-with-lease if you are sure it should be replaced."
		failed=`expr $failed + 1`
		printf '  %-26s %s\n' "$job_$dev" "PUSH FAILED" >> "$sumfile"
	fi
	rm -f /tmp/devpush.$$

	# ---- prove abdopuppet really has that commit -----------------------
	now=`git ls-remote --heads "$origin" "$branch" 2>/dev/null | awk 'NR==1 { print $1 }'`
	if [ "$now" = "$src_sha" ]; then
		echo "  verified: abdopuppet now has $now"
		printf '  %-26s %s\n' "$job_$dev" "$src_sha" >> "$sumfile"
	else
		echo "  *** abdopuppet reports '$now', expected $src_sha"
		failed=`expr $failed + 1`
		printf '  %-26s %s\n' "$job_$dev" "*** MISMATCH, has ${now:-nothing}" >> "$sumfile"
	fi
	sync
done

echo
echo '###########################################'
echo "  branch $branch  ->  abdopuppet, for $dev"
echo "  pushed            : $ok"
echo "  already identical : $skipped"
[ "$missingb" -gt 0 ] && echo "  not on github      : $missingb"
[ "$failed" -gt 0 ] && echo "  failed             : $failed"
echo ""
echo "  commits"
echo "  --------------------------------------------------------------"
printf "  %-26s %s\n" "repository" "commit on abdopuppet"
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
