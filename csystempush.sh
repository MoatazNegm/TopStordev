#!/bin/sh
# csystempush.sh -- CONTAINER variant of systempush.sh (the plain script hands over to this one in the container
# flavour). Identical except for the software-container check: see csoftware_ready below.
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
#   SPD_EXCLUDE_COMMON     untracked in every project (default: the ui bundle)
#   SPD_EXCLUDE_TOPSTORWEB extra exclusions for topstorweb only
#   SPD_PROJECTS       space separated project directory names
#   SPD_ROOT           prefix to put in front of every path (default none)
#
# About the exclusions.  They are removed from the index but LEFT ON DISK, and
# each one is added to .gitignore.  That last part matters: .gitignore on its
# own does nothing to a file that is already tracked, which is how a 75 MB
# ui bundle and 74 MB of source maps ended up in every branch in the first
# place.  Anything listed below has to be taken out of the index as well.
#
# topstorweb is built around this: only src/ -- the react source -- is pushed.
# Every server rebuilds it with the node_modules that came in the deployment
# image, and vite writes the result to build_react/, which is not tracked.
# Measured on this repo, from QSD5.179 to HEAD only 7 paths changed and every
# one of them was under src/: 0.1 MB out of 266.4 MB, so 99.9% of the tree
# never changes and is already sitting in the image.
#
# How each directory was classified, by what actually references it:
#
#   src/      THE react source.  vite's entry is index.html -> /src/main.jsx.
#             This is the only thing that travels.                    KEEP
#   dist/     /dist/css/* and /dist/js/* in index.html; vite proxies
#             /dist to Apache, so Apache serves it off the image.  DROP
#   plugins/  jQuery, bootstrap, select2, fontawesome in index.html, same
#             proxy.  Vendored libraries, never edited by hand.     DROP
#   public/   vite's publicDir -- copied verbatim into build_react/.
#             It must EXIST ON DISK for the build, it just never
#             travels, because the image already has it.           DROP
#   Data/     src reads Data/DomName.txt etc, but through
#             api.get('requestdata.php', {file: ...}) -- PHP reads it
#             server side, it is not a build input.                 DROP
#   img/      one asset, img/invaliddisk.png, served by Apache.     DROP
#   js/ css/  assets/ ar/ fonts/     zero references from src/, dozens
#             from the legacy *.php pages -- pure apache.          DROP
#   netdata/  zero references from src/, 2 from php.               DROP
#
# Two of these have to be present on disk for the app to work at all, so
# they must come from the image rather than from a branch:
#   public/   vite copies it into the build; if it is missing the UI loses
#             /dist/css/*.css and renders unstyled
#   Data/     requestdata.php reads these on every page load
#
# The cost of that: once a path is untracked AND ignored, git cannot see edits
# to it at all, by design.  If one of these ever has to change, the change
# belongs in the deployment image, not in a branch.  The script does check for
# edits to an excluded path at the moment it drops it and shouts if it finds
# any, but it cannot warn about edits made after that.
#
# To narrow or widen the list:
#   SPD_EXCLUDE_TOPSTORWEB='node_modules/ build_react/ .vite/ dist/ plugins/ \
#                          dashboarddev3/ *.zip *.tar *.tar.gz *.map' \
#     /TopStor/systempush.sh QSD5.199
# ---------------------------------------------------------------------------

SPD_PUSH_FORCE=${SPD_PUSH_FORCE:-0}
SPD_EXCLUDE_COMMON=${SPD_EXCLUDE_COMMON:-'quickstor-ui.tar.gz'}
SPD_EXCLUDE_TOPSTORWEB=${SPD_EXCLUDE_TOPSTORWEB:-'node_modules/ build_react/ build_react.bak/ .vite/ dist/ plugins/ dashboarddev3/ public/ assets/ ar/ js/ css/ img/ fonts/ netdata/ Data/ *.zip *.tar *.tar.gz *.map'}
SPD_PROJECTS=${SPD_PROJECTS:-'TopStor pace topstorweb'}
SPD_ROOT=${SPD_ROOT:-}
PROJECTS=$SPD_PROJECTS

# which exclusions apply to this project
excludes_for() {
	case $1 in
	topstorweb) echo "$SPD_EXCLUDE_COMMON $SPD_EXCLUDE_TOPSTORWEB" ;;
	*)          echo "$SPD_EXCLUDE_COMMON" ;;
	esac
}

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
	job=$2
	dir=`pwd`

	if [ ! -e .git ]; then
		echo "  $dir is not a git repository"
		return 1
	fi

	# ---- 1 and 2. stage everything, minus what must never be committed ---
	# per-branch pre_apply / post_apply hook stubs (apply.d/<branch>/), TopStor only
	if [ "$job" = "TopStor" ] && [ -f ./mkapplyhooks.sh ]; then
		sh ./mkapplyhooks.sh "$branch" .
	fi

	git add --all

	# __pycache__ turns up at any depth, so a bare '__py*' pathspec is not
	# enough -- it only ever matches the top level.  :(glob)** reaches them all.
	git rm -rq --ignore-unmatch -- ':(glob)**/__py*' >/dev/null 2>&1
	find . -name '.git' -prune -o -name '__py*' -prune -exec rm -rf {} + 2>/dev/null

	# Build artefacts: untracked, but deliberately LEFT ON DISK.  These are
	# files you still want on the node, you just do not want them in git.
	# Everything here is either regenerable or already ignored, but .gitignore
	# does NOT stop it on its own -- once a file is tracked the ignore rules
	# are never applied to it again.  So it has to leave the index too.
	#
	# set -f matters: without it the shell expands '*' in these patterns
	# against the working directory before the loop ever sees them, so
	# '*.zip' silently turns into whichever single file happens to match.
	set -f
	for pat in `excludes_for "$job"`; do
		# a pattern with no slash in it should match at any depth
		case $pat in
		*/*) spec=$pat ;;
		*)   spec=":(glob)**/$pat" ;;
		esac

		# A file that is still tracked AND has been edited is about to be
		# dropped, and that edit would not be committed.  Say so before it
		# happens.  --diff-filter=M matters: without it every file merely
		# being untracked shows up here too and the warning cries wolf.
		#
		# This only covers the transition.  Once a path is untracked and
		# ignored git cannot see edits to it at all, by design -- so a later
		# change to one of these has to be made in the deployment image.
		edited=`git diff --name-only --diff-filter=M HEAD -- "$spec" 2>/dev/null`
		if [ -n "$edited" ]; then
			n=`echo "$edited" | wc -l`
			echo "  *** WARNING: $n EDITED file(s) under $pat will NOT be committed:"
			echo "$edited" | head -5 | sed 's/^/         /'
			[ "$n" -gt 5 ] && echo "         ... and $((n - 5)) more"
		fi

		# no -q here: git rm lists what it removed, and the count is the
		# only honest way to say how much actually came out
		removed=`git rm -r --cached --ignore-unmatch -- "$spec" 2>/dev/null | wc -l`
		if [ "$removed" -gt 0 ]; then
			echo "  untracked $pat ($removed files, still on disk)"
		fi

		if ! grep -qxF "$pat" .gitignore 2>/dev/null; then
			echo "$pat" >> .gitignore
			echo "  added '$pat' to .gitignore"
		fi
	done
	set +f

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
	fnupdate "$branch" "$job" || rc=1
done

echo
echo '###########################################'
echo "  syncing the cluster"
# The cluster sync only makes sense on a real node, so SPD_ROOT overrides skip it.
if [ -z "$SPD_ROOT" ]; then
	cd /TopStor 2>/dev/null
	if csoftware_ready "`docker exec etcdclient /TopStor/etcdgetlocal.py clusternodeip`"; then
		myhost=`docker exec etcdclient /TopStor/etcdgetlocal.py clusternode`
		leaderip=`docker exec etcdclient /TopStor/etcdgetlocal.py leaderip`
		stamp=`date +%s`
		/TopStor/etcddel.py $leaderip sync/cversion --prefix
		/TopStor/etcdput.py $leaderip sync/cversion/_${branch}__/request cversion_$stamp
		/TopStor/etcdput.py $leaderip sync/cversion/_${branch}__/request/$myhost cversion_$stamp
		/TopStor/myrepopush.sh $branch
	else
		echo "  the software container is not ready .... skipping the cluster sync"
		rc=0
	fi
else
	echo "  SPD_ROOT is set .... skipping the cluster sync"
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
	if [ "$b" = "$branch" ]; then
		# ask origin directly rather than trusting that the push worked
		rem=`git ls-remote origin "refs/heads/$branch" 2>/dev/null | awk 'NR==1 { print $1 }'`
		if [ "$rem" = "$s" ]; then
			flag="   origin has this exact commit"
		elif [ -z "$rem" ]; then
			flag="   <-- NOT on origin"
		else
			flag="   <-- origin has $rem, which is a different commit"
		fi
	else
		flag="   <-- NOT on $branch"
	fi
	printf "  %-11s %-16s %-42s %s%s\n" "$job" "$b" "$s" "$k" "$flag"
done
echo "  --------------------------------------------------------------"

echo
if [ "$rc" -ne 0 ]; then
	echo "finished, with errors"
	exit 1
fi
echo "finished"
exit 0
