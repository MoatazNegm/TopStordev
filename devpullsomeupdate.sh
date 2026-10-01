#!/usr/bin/sh
# ---------------------------------------------------------------------------
# devpullsomeupdate.sh <branch> <developer> [repository ...]
# devpullsomeupdate.sh <anything> <new-developer> init [clone] [repository ...]
#
# Take one of a developer's branches off their github fork and land it on
# abdopuppet, ready for you to review and merge into a newer QSD line.
#
#   repositories:  TopStor   pace   topstorweb      (default: all three)
#                 "all" means all three.  A name may also be any unique part
#                 of one, so "web" picks topstorweb.  Listing more than one
#                 is fine.
#
#   developer:     the whole name, or any part of it that fits exactly one
#                 developer, so "Ahmed" finds Ahmed395593.  Two developers
#                 containing the same part is an error, never a guess.
#
# The developer directories are /TopStor_<developer>, /pace_<developer> and
# /topstorweb_<developer>, so a developer's full name is whatever follows the
# underscore.  Both the repository and the developer argument are resolved
# before any work starts, and an unresolvable or ambiguous one stops the run
# rather than half way through it.
#
# Making room for a NEW developer:
#   'init' in the repository position is a mode rather than a project, and
#   none of the three is called init so the two can never collide.  The name
#   given is then taken whole -- nothing is matched against anybody -- and the
#   directories are created:
#     devpullsomeupdate.sh - Ahmed123 init          the three empty directories
#     devpullsomeupdate.sh - Ahmed123 init clone    also clone and set remotes
#     devpullsomeupdate.sh - Ahmed123 init pace     just the one repository
#   There is no bookkeeping to keep, because the developer list is read back
#   out of the directories themselves, so a new name is immediately usable as
#   a full name and as a unique part of one.  Running init twice is safe: the
#   directories that are already there are reported and left alone.
#
#   'clone' is deliberately a separate word.  A fresh TopStor from abdopuppet
#   is around 860 MB, and that should never happen because someone typed
#   'init' expecting a directory.
#
#   The fork remote is https://github.com/<developer>/<project>_mydev.git,
#   which need not exist yet -- a remote is only a name and an address until
#   something is fetched from it, so the developer can be set up before they
#   have created anything on github.
#
# The branch is taken from the developer's fork EXACTLY AS IT IS.  Nothing is
# merged, rebased or committed on the way through: the commit that lands on
# abdopuppet is the same commit the developer pushed, and that is proved with
# a fresh ls-remote afterwards rather than assumed.
#
# Which github side?  Always the developer's own fork, matched on the url
# containing their name.  These repositories also carry a 'QuickStor' remote
# pointing at the upstream account, and BOTH urls contain the word github, so
# the old 'git remote -v | grep github | grep $2 | head -1' could take the
# wrong one depending on line order.  Naming the rule explicitly means a pull
# meant for a developer can never quietly read from upstream instead.
#
# What this replaces, and why:
#   * the tempb parking branch, the delete-then-recreate dance and the
#     duplicated block of worktree clean-ups are gone.  tempb only ever
#     existed to step off the branch so 'git branch -D' would accept it;
#     'git checkout -B' resets a branch in place and needs none of it.
#   * the developer was found with 'ls / | grep $dev | grep TopStor' and a
#     vague "more than one match" check.  The directories are now looked up by
#     name, and a wrong developer name lists the ones that do exist.
#   * a repository the developer does not have, or a branch they never pushed
#     to it, used to abort the whole run half way.  Each is now reported and
#     stepped over, so the repositories that do have it still get updated.
#   * there was no way to say "only topstorweb"; it always pushed all three.
#
# Shallow aware: in a shallow repository an ordinary fetch leaves the boundary
# where it is, so the old history is never re-downloaded.  The boundary is
# printed, and a branch that does not descend from the base is reported
# rather than quietly producing an empty merge-base at review time.
#
# environment:
#   DEV_PROXY_BASE       base the image is built on (default QSD5.179)
#   DEV_PROXY_LATEST     newest QSD5.<n> on abdopuppet to compare against
#                       (default: worked out from the remote)
#   DEV_PROXY_FORCE=1    push with --force-with-lease
#   DEV_PROXY_SKIP=0     fetch the full history even in a shallow repo
# ---------------------------------------------------------------------------

DEV_PROXY_BASE=${DEV_PROXY_BASE:-QSD5.179}
DEV_PROXY_LATEST=${DEV_PROXY_LATEST:-}
DEV_PROXY_FORCE=${DEV_PROXY_FORCE:-0}
DEV_PROXY_SKIP=${DEV_PROXY_SKIP:-0}
ALL_PROJECTS='TopStor pace topstorweb'

# A developer is whoever has a directory for one of the projects.  Looking at
# all three, not just TopStor, means somebody who only ever touched pace or
# topstorweb still shows up in the 'does not exist' hint below.
list_developers() {
	for job in $ALL_PROJECTS; do
		for d in /${job}_*; do
			[ -d "$d" ] || continue
			echo "$d" | sed 's#^/'"$job"'_##'
		done
	done | sort -u
}

branch=$1
dev=$2
shift 2 2>/dev/null

# An 'init' in the repository position is a mode, not a repository.  No
# project is called init, so the two can never be confused, and the mode is
# taken before anything else is resolved.
INIT=0
CLONE=0
if [ "${1:-}" = "init" ]; then
	INIT=1
	shift
	if [ "${1:-}" = "clone" ]; then
		CLONE=1
		shift
	fi
fi
want="$*"

if [ -z "$branch" ] || [ -z "$dev" ]; then
	echo "usage: devpullsomeupdate.sh <branch> <developer> [repository ...]" >&2
	echo "  takes <branch> from that developer's github fork and lands it on" >&2
	echo "  abdopuppet, so you can review it and merge it into a newer QSD." >&2
	echo "" >&2
	echo "  repositories: $ALL_PROJECTS    (default all three, or say 'all')" >&2
	echo "                a unique part of a name works too, e.g. 'web'" >&2
	echo "" >&2
	echo "  developer:     the whole name, or any part of it that fits one" >&2
	echo "                developer only, e.g. 'Ahmed' for Ahmed395593" >&2
	echo "" >&2
	echo "  to make room for a NEW developer, whose name is then used whole:" >&2
	echo "    devpullsomeupdate.sh <anything> <new-developer> init" >&2
	echo "      creates /$project_<developer> for each project, so that any" >&2
	echo "      part of the new name works from then on.  Add 'clone' after" >&2
	echo "      init to also clone them and set the three remotes up." >&2
	echo "" >&2
	echo "developers that exist:" >&2
	list_developers | sed 's/^/    /' >&2
	exit 1
fi

# Each project is one directory here, but it is called something else on
# abdopuppet and on github.  pace is HC and topstorweb is TopStorweb, which is
# exactly the sort of thing worth writing down once instead of remembering.
repo_name() {
	case $1 in
	TopStor) echo TopStordev ;;
	pace) echo HC ;;
	topstorweb) echo TopStorweb ;;
	esac
}

# ---- init: make room for a developer --------------------------------------
if [ "$INIT" = 1 ]; then
	case $dev in
	'') echo "init needs the name of the developer to make room for" >&2; exit 1 ;;
	*/*) echo "'$dev' cannot be used, it contains a '/'" >&2; exit 1 ;;
	esac
	if ! echo "$dev" | grep -q '^[A-Za-z0-9][A-Za-z0-9._-]*$'; then
		echo "'$dev' cannot be used as a directory name." >&2
		echo "  letters, digits, dot, dash and underscore only" >&2
		exit 1
	fi

	# resolve the repositories the same way, so 'init pace' is allowed
	projects=""
	if [ -z "$want" ] || [ "$want" = "all" ]; then
		projects=$ALL_PROJECTS
	else
		for w in $want; do
			found=""
			n=0
			for job in $ALL_PROJECTS; do
				case $job in
				*"$w"* | "$w"*)
					n=`expr $n + 1`
					found=$job
					;;
				esac
			done
			case $n in
			0) echo "'$w' does not name any of: $ALL_PROJECTS" >&2; exit 1 ;;
			1) projects="$projects $found" ;;
			*) echo "'$w' matches more than one of: $ALL_PROJECTS" >&2; exit 1 ;;
			esac
		done
	fi

	echo "init: making room for the developer $dev"
	echo "  repositories: $projects"
	echo ""

	made=""
	already=""
	for job in $projects; do
		d="/${job}_$dev"
		if [ -d "$d" ]; then
			echo "  $d  already there, left alone"
			already="$already $d"
			continue
		fi
		if mkdir -p "$d" 2>/dev/null; then
			echo "  $d  created"
			made="$made $d"
		else
			echo "  $d  COULD NOT BE CREATED"
		fi
	done

	# ---- optionally make them real working copies ----------------------
	if [ "$CLONE" = 1 ]; then
		echo ""
		echo "  cloning from abdopuppet, which also sets the fork remote up:"
		for job in $projects; do
			rn=`repo_name $job`
			d="/${job}_$dev"
			if [ ! -d "$d" ]; then
				echo "    $job  no directory, skipped"
				continue
			fi
			if [ -d "$d/.git" ]; then
				echo "    $job  already a git repository, left alone"
				continue
			fi
			echo "    $job  cloning $rn from abdopuppet, this takes a while"
			if git clone -q "http://10.11.11.252/git/$rn.git" "$d" 2>/tmp/initclone.$$; then
				cd "$d" || continue
				# the fork need not exist yet: a remote is only a name and
				# an address until something is fetched from it
				git remote add QuickStor "https://github.com/MoatazNegm/$rn.git" 2>/dev/null
				git remote add remote "https://github.com/$dev/${job}_mydev.git" 2>/dev/null
				latest=`git ls-remote --heads origin 2>/dev/null | awk '{print $2}' \
					| sed 's#refs/heads/##' | grep '^QSD5\.[0-9]' \
					| sed 's/^QSD5\.//' | sort -n | tail -1 | sed 's/^/QSD5./'`
				if [ -n "$latest" ] && git rev-parse --verify --quiet "origin/$latest" >/dev/null; then
					git checkout -q -B "$latest" "origin/$latest" 2>/dev/null \
						&& echo "      on $latest, ready to branch from"
				else
					git checkout -q "$(git branch -r 2>/dev/null | head -1 | sed 's/^ *//;s#origin/##')" 2>/dev/null
				fi
				echo "      fork remote : https://github.com/$dev/${job}_mydev.git"
				cd / || continue
			else
				echo "      CLONE FAILED:"
				sed 's/^/        /' /tmp/initclone.$$ | head -4
			fi
		done
		rm -f /tmp/initclone.$$
	fi

	echo ""
	# warn before a future partial name becomes ambiguous
	others=""
	for cand in `list_developers`; do
		[ "$cand" = "$dev" ] && continue
		case $cand in
		*"$dev"* | "$dev"*) others="$others $cand" ;;
		esac
	done
	if [ -n "$others" ]; then
		echo "  note: the name $dev overlaps $others, so a short part of a"
		echo "        name may match more than one developer from now on."
		echo "        Partial names that fit more than one are refused, not guessed."
	fi

	echo ""
	if [ -n "$made" ]; then
		echo "  ready: `echo $made`"
		echo "  from now on any part of '$dev' that fits only them selects them,"
		echo "  so  devpullsomeupdate.sh <branch> ${dev%%[0-9]*}  will work."
	else
		echo "  nothing new was created; those directories were already there."
	fi
	if [ "$CLONE" != 1 ] && [ -n "$made" ]; then
		echo ""
		echo "  they are empty directories for now.  To clone and wire up the"
		echo "  remotes as well, repeat with clone after init:"
		echo "    devpullsomeupdate.sh $branch $dev init clone"
	fi
	echo ""
	echo "finished"
	exit 0
fi

# ---- which developer did the caller mean? ---------------------------------
# The repositories are /TopStor_<developer>, /pace_<developer> and
# /topstorweb_<developer>, so the whole of a developer's name is whatever
# follows the underscore.  Accepting any part of it means you can type 'Ahmed'
# instead of 'Ahmed395593', on the same rule the repositories use: an exact
# name always wins, one part that fits is taken, and two is an error rather
# than a guess.
devs=`list_developers`
devmatch=""
n=0
for cand in $devs; do
	if [ "$cand" = "$dev" ]; then
		devmatch=$cand
		n=1
		break
	fi
done
if [ "$n" -eq 0 ]; then
	want_lc=`echo "$dev" | tr 'A-Z' 'a-z'`
	hits=""
	for cand in $devs; do
		case `echo "$cand" | tr 'A-Z' 'a-z'` in
		*"$want_lc"*)
			n=`expr $n + 1`
			hits="$hits $cand"
			;;
		esac
	done
	case $n in
	1) devmatch=`echo $hits` ;;
	esac
fi

case $n in
0)
	echo "no developer matching '$dev'." >&2
	echo "" >&2
	echo "developers that do exist:" >&2
	echo "$devs" | tr ' ' '\n' | grep -v '^$' | sed 's/^/    /' >&2
	exit 1
	;;
1) ;;
*)
	echo "'$dev' matches more than one developer, so it is not safe to guess:" >&2
	echo "$hits" | tr ' ' '\n' | grep -v '^$' | sed 's/^/    /' >&2
	echo "" >&2
	echo "give the whole name of the one you mean." >&2
	exit 1
	;;
esac

if [ "$devmatch" != "$dev" ]; then
	echo "'$dev' is taken as the developer $devmatch"
fi
dev=$devmatch

# ---- which repositories did the caller ask for? ---------------------------
projects=""
if [ -z "$want" ] || [ "$want" = "all" ]; then
	projects=$ALL_PROJECTS
else
	for w in $want; do
		found=""
		n=0
		for job in $ALL_PROJECTS; do
			case $job in
			*"$w"* | "$w"*)
				n=`expr $n + 1`
				found=$job
				;;
			esac
		done
		case $n in
		0) echo "'$w' does not name any of: $ALL_PROJECTS" >&2; exit 1 ;;
		1) projects="$projects $found" ;;
		*) echo "'$w' matches more than one of: $ALL_PROJECTS" >&2; exit 1 ;;
		esac
	done
fi

# ---- does this developer have those repositories? --------------------------
dirs=""
missing=""
for job in $projects; do
	d="/${job}_$dev"
	if [ -d "$d" ]; then
		dirs="$dirs $d"
	else
		missing="$missing $d"
	fi
done

if [ -z "$dirs" ]; then
	echo "developer '$dev' has none of those repositories." >&2
	echo "$missing" | tr ' ' '\n' | grep -v '^$' | sed 's/^/    missing: /' >&2
	echo "" >&2
	echo "the directories that do exist for $dev:" >&2
	ls -d /TopStor_$dev /pace_$dev /topstorweb_$dev 2>/dev/null | sed 's/^/    /' >&2
	exit 1
fi

# github needs a working resolver
if [ -w /etc/resolv.conf ]; then
	echo 'nameserver 8.8.8.8' > /etc/resolv.conf 2>/dev/null
fi

pick_remote() {
	want_url=$1; label=$2
	git remote -v 2>/dev/null | awk '!/\(push\)/ && $2 != "" { print $1 "\t" $2 }' \
		| while IFS='	' read -r name url; do
			case $url in
			*$want_url*) echo "$name|$url" ;;
			esac
		done > /tmp/devremote.$$
	n=`wc -l < /tmp/devremote.$$`
	if [ "$n" = 1 ]; then
		cut -d'|' -f1 /tmp/devremote.$$
	elif [ "$n" -gt 1 ]; then
		echo "  ERROR: $label is ambiguous, more than one remote matches '$want_url':" >&2
		sed 's/^/          /' /tmp/devremote.$$ >&2
	fi
	rm -f /tmp/devremote.$$
}

echo "devpullsomeupdate: $branch from the fork of $dev -> abdopuppet"
echo "  repositories: $projects"

sumfile=/tmp/devpullsomeupdate.summary.$$
: > "$sumfile"

ok=0
skipped=0
nobranch=0
failed=0

for job in $projects; do
	dir="/${job}_$dev"
	echo
	echo '###########################################'
	echo "  $dir"
	if [ ! -d "$dir" ]; then
		echo "  the developer has no $job repository -- stepping over it"
		printf '  %-26s %s\n' "${job}_$dev" "no $job repository for $dev" >> "$sumfile"
		nobranch=`expr $nobranch + 1`
		continue
	fi
	cd "$dir" || { failed=`expr $failed + 1`; continue; }

	if ! git rev-parse --git-dir >/dev/null 2>&1; then
		echo "  ERROR: $dir is not a git repository"
		printf '  %-26s %s\n' "${job}_$dev" "not a git repository" >> "$sumfile"
		failed=`expr $failed + 1`
		continue
	fi

	devfork=`pick_remote "$dev" 'the developer fork'`
	if [ -z "$devfork" ]; then
		echo "  ERROR: no remote matching this developer '$dev'"
		echo "         the remotes here are:"
		git remote -v | sed 's/^/           /'
		failed=`expr $failed + 1`
		printf '  %-26s %s\n' "${job}_$dev" "no fork for $dev" >> "$sumfile"
		continue
	fi
	origin=`pick_remote 252 'abdopuppet'`
	if [ -z "$origin" ]; then
		echo "  ERROR: no remote pointing at abdopuppet (url containing 252)"
		failed=`expr $failed + 1`
		printf '  %-26s %s\n' "${job}_$dev" "no abdopuppet remote" >> "$sumfile"
		continue
	fi
	echo "  from : $devfork"
	echo "  to   : $origin"

	# ---- ask before fetching -------------------------------------------
	# A branch the developer never pushed is the common case -- they may have
	# only worked on one repository.  Fetching a ref that does not exist fails
	# with "could not fetch", which reads like a broken network rather than
	# "they did not push that one".  ls-remote moves no objects and says so
	# plainly.
	have=`git ls-remote --heads "$devfork" "$branch" 2>/dev/null | awk 'NR==1 { print $1 }'`
	if [ -z "$have" ]; then
		echo "  the fork has no branch '$branch' -- stepping over it"
		nobranch=`expr $nobranch + 1`
		printf '  %-26s %s\n' "${job}_$dev" "no '$branch' on their fork" >> "$sumfile"
		continue
	fi

	# ---- fetch the developer's branch ----------------------------------
	if [ -f .git/shallow ] && [ "$DEV_PROXY_SKIP" = 0 ]; then
		echo "  shallow repository -- boundary stays at `head -1 .git/shallow`"
	fi
	echo "  fetching $devfork/$branch"
	if ! git fetch --no-tags --prune "$devfork" \
			"+refs/heads/$branch:refs/remotes/$devfork/$branch"; then
		echo "  ERROR: could not fetch $branch from $devfork"
		failed=`expr $failed + 1`
		printf '  %-26s %s\n' "${job}_$dev" "FETCH FAILED" >> "$sumfile"
		continue
	fi

	if ! git rev-parse --verify --quiet "refs/remotes/$devfork/$branch" >/dev/null; then
		echo "  *** ERROR: $devfork has $branch but the fetch did not bring it in"
		failed=`expr $failed + 1`
		printf '  %-26s %s\n' "${job}_$dev" "FETCH INCOMPLETE" >> "$sumfile"
		continue
	fi

	src_sha=`git rev-parse "refs/remotes/$devfork/$branch"`
	echo "  the branch is $src_sha on their fork"

	# ---- pre-flight, for your review step ------------------------------
	echo ""
	echo "  ${branch} against the QSD line:"

	# The whole point of this run is that the developer branched off a QSD and
	# not off something of their own, so the base is checked properly rather
	# than skipped.  A developer clone often does not have the base branch
	# sitting in it at all, in which case it is worth one quiet fetch before
	# saying anything about it.
	if ! git rev-parse --verify --quiet "$DEV_PROXY_BASE" >/dev/null; then
		git fetch --no-tags -q "$origin" \
			"+refs/heads/$DEV_PROXY_BASE:refs/remotes/$origin/$DEV_PROXY_BASE" 2>/dev/null
	fi
	if git rev-parse --verify --quiet "$DEV_PROXY_BASE" >/dev/null \
	   || git rev-parse --verify --quiet "refs/remotes/$origin/$DEV_PROXY_BASE" >/dev/null; then
		base=$DEV_PROXY_BASE
		git rev-parse --verify --quiet "$base" >/dev/null || base="refs/remotes/$origin/$base"
		if git merge-base --is-ancestor "$base" "refs/remotes/$devfork/$branch" 2>/dev/null; then
			echo "    descends from $DEV_PROXY_BASE : yes"
		else
			echo "    descends from $DEV_PROXY_BASE : NO"
			if [ -f .git/shallow ]; then
				echo "      (a shallow repository cannot see far enough to tell for"
				echo "       certain -- fetch the full history if this matters)"
			else
				echo "      this branch was NOT cut from $DEV_PROXY_BASE, so the"
				echo "      diff you review will include whatever else it is based on"
			fi
		fi
	else
		echo "    $DEV_PROXY_BASE is not on $origin, so the base could not be checked"
	fi

	latest=$DEV_PROXY_LATEST
	if [ -z "$latest" ]; then
		latest=`timeout 60 git ls-remote --heads "$origin" 2>/dev/null \
			| awk '{print $2}' | sed 's#refs/heads/##' \
			| grep '^QSD5\.[0-9]' | sed 's/^QSD5\.//' | sort -n | tail -1 \
			| sed 's/^/QSD5./'`
	fi
	if [ -n "$latest" ] && [ "$latest" != "$branch" ]; then
		git fetch --no-tags -q "$origin" \
			"+refs/heads/$latest:refs/remotes/$origin/$latest" 2>/dev/null
		if git rev-parse --verify --quiet "refs/remotes/$origin/$latest" >/dev/null; then
			mb=`git merge-base "refs/remotes/$devfork/$branch" "refs/remotes/$origin/$latest" 2>/dev/null`
			ab=`git rev-list --left-right --count \
					"refs/remotes/$origin/$latest...refs/remotes/$devfork/$branch" 2>/dev/null`
			ahead=`echo $ab | awk '{print $2}'`
			echo "    merge-base with $latest : ${mb:-none (unrelated histories)}"
			echo "    $latest is `echo $ab | awk '{print $1}'` commit(s) ahead, and this branch is $ahead commit(s) ahead"
			if [ "$ahead" = 0 ]; then
				echo "    -> this branch is already inside $latest; there is nothing"
				echo "       left to merge, whatever its name says"
			else
				echo "    -> merging it in will move $latest forward by $ahead commit(s)"
			fi
		fi
	else
		echo "    no other QSD line on $origin to compare against"
	fi
	echo ""

	dst_sha=`git ls-remote --heads "$origin" "$branch" 2>/dev/null | awk 'NR==1 { print $1 }'`
	if [ "$dst_sha" = "$src_sha" ]; then
		echo "  abdopuppet already has $src_sha -- nothing to do"
		printf '  %-26s %s\n' "${job}_$dev" "$src_sha" >> "$sumfile"
		skipped=`expr $skipped + 1`
		continue
	fi
	if [ -n "$dst_sha" ]; then
		echo "  abdopuppet has $dst_sha for this branch -- it will be replaced"
		echo "  only if the push is a fast forward.  If the developer rebased"
		echo "  after you last touched it, the push is refused on purpose."
	fi

	# ---- take it as it is ----------------------------------------------
	if ! git checkout -f -B "$branch" "refs/remotes/$devfork/$branch"; then
		echo "  ERROR: could not check out $branch"
		failed=`expr $failed + 1`
		printf '  %-26s %s\n' "${job}_$dev" "CHECKOUT FAILED" >> "$sumfile"
		continue
	fi
	git reset --hard --quiet
	git clean -f
	git config --replace-all pull.rebase false
	git checkout -- * 2>/dev/null
	# python cache turns up at any depth; a bare '__py*' pathspec only ever
	# matched the top level
	git rm -rq --ignore-unmatch -- ':(glob)**/__py*' >/dev/null 2>&1
	find . -name '.git' -prune -o -name '__py*' -prune -exec rm -rf {} + 2>/dev/null

	got=`git rev-parse HEAD`
	if [ "$got" != "$src_sha" ]; then
		echo "  *** ERROR: HEAD is $got but $devfork/$branch is $src_sha"
		failed=`expr $failed + 1`
		printf '  %-26s %s\n' "${job}_$dev" "*** MISMATCH, HEAD $got" >> "$sumfile"
		continue
	fi
	echo "  local branch is $got, exactly as the developer pushed it"

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
		git fetch --no-tags --unshallow "$devfork" >/dev/null 2>&1
		if git push $pushflags "$origin" "$branch" > /tmp/devpush.$$ 2>&1; then
			echo "  PUSHED on the second attempt"
			ok=`expr $ok + 1`
		else
			sed 's/^/     /' /tmp/devpush.$$ | head -6
			failed=`expr $failed + 1`
			printf '  %-26s %s\n' "${job}_$dev" "PUSH FAILED" >> "$sumfile"
		fi
	else
		sed 's/^/     /' /tmp/devpush.$$ | head -8
		echo "  abdopuppet has commits on this branch that are not in the"
		echo "  developer's copy, so a non fast-forward push is refused.  That"
		echo "  is the safe answer: resolve it deliberately with a merge rather"
		echo "  than DEV_PROXY_FORCE=1, unless you are sure it should be replaced."
		failed=`expr $failed + 1`
		printf '  %-26s %s\n' "${job}_$dev" "PUSH REFUSED (not fast forward)" >> "$sumfile"
	fi
	rm -f /tmp/devpush.$$

	# ---- prove abdopuppet really has that commit -----------------------
	now=`git ls-remote --heads "$origin" "$branch" 2>/dev/null | awk 'NR==1 { print $1 }'`
	if [ "$now" = "$src_sha" ]; then
		echo "  verified: abdopuppet now has $now"
		printf '  %-26s %s\n' "${job}_$dev" "$src_sha" >> "$sumfile"
	else
		echo "  *** abdopuppet reports '$now', expected $src_sha"
		failed=`expr $failed + 1`
		printf '  %-26s %s\n' "${job}_$dev" "*** MISMATCH, has ${now:-nothing}" >> "$sumfile"
	fi
	sync
done

echo
echo '###########################################'
echo "  branch $branch  ->  abdopuppet, for $dev"
echo "  pushed            : $ok"
echo "  already identical : $skipped"
[ "$nobranch" -gt 0 ] && echo "  nothing to take   : $nobranch"
[ "$failed" -gt 0 ] && echo "  failed            : $failed"
echo ""
echo "  commits"
echo "  --------------------------------------------------------------"
printf "  %-26s %s\n" "repository" "commit on abdopuppet"
cat "$sumfile"
echo "  --------------------------------------------------------------"
echo ""
echo "  next: review it with systempregetdiff.sh, then merge it into the"
echo "  newer QSD line the same way."
rm -f "$sumfile"

echo
cd /TopStor 2>/dev/null
if [ "$failed" -gt 0 ]; then
	echo "finished, with errors"
	exit 1
fi
echo "finished"
exit 0
