#!/bin/sh
#
# systemmerge.sh
# =============
#
# Merge the branch named on the command line INTO the branch that each of the
# three TopStor repositories is currently sitting on.
#
#     systemmerge.sh [options] <branch> [<branch> ...]
#
# The previous version of this script merged "one commit over the other"
# because of three defects, all of them silent:
#
#   1. The exit status of "git merge" was never checked (the check was
#      commented out).  A conflicting merge therefore left the repository
#      with conflict markers in the work tree, still printed "finished",
#      and told the user to run systempush.sh - which does
#      "git add --all; git commit; git push" and publishes <<<<<<< HEAD
#      markers to the shared branch.
#
#   2. "currentbranch" was calculated ONCE, from /TopStor, and then reused for
#      all three repositories.  The three repositories are routinely sitting
#      on three DIFFERENT branches, so two of the three merges were created
#      from the wrong base.
#
#   3. When the argument branch was already merged (git reports
#      "Already up to date.") the script produced an empty difference and
#      still reported success.
#
# What this version does, per repository:
#
#   * works out ITS OWN current branch,
#   * refreshes it from origin with a fast-forward only (never discards work),
#   * creates <argument>_<current> from that tip,
#   * merges with --no-ff and CHECKS the exit status,
#   * classifies every changed file as added / deleted / modified and says
#     WHICH branch contributed it and which side won where they overlapped,
#   * leaves a merge conflict in place but refuses to call it a success.
#
# The result is recorded in $MERGE_MANIFEST so that systemgetdiff.sh can show
# a truthful per-branch summary instead of guessing from the branch name.
#

REPOS="${SYSTEM_REPOS:-TopStor pace topstorweb}"
ROOT="${SYSTEM_ROOT:-}"
MERGE_MANIFEST="${MERGE_MANIFEST:-/root/.systemmerge_manifest}"

OPT_PULL=0
OPT_DRY=0
OPT_FORCE=0
RC_OVERALL=0

usage() {
	cat <<'EOF'
usage: systemmerge.sh [options] <branch> [<branch> ...]

  <branch>   branch to merge INTO the branch each repository is currently on.
             The merged branch is named  <argument>_<current>.

options:
  --pull     additionally run /TopStor/systempull.sh, the way the old script
             did.  NOTE: systempull.sh is a deployment script - it pushes to
             the cluster etcd and runs pre_apply.sh and myrepopush.sh, and it
             runs "git checkout -- *" which throws away uncommitted work.
             It is therefore no longer the default.
  --dry-run  report what would be merged and change nothing.
  --force    merge even when the argument branch is already merged into the
             current one (git would otherwise just say "Already up to date."
             and produce no change at all).
  -h,--help  this text.

After a clean run, review the result and then push the merged branch.
EOF
}

say()  { printf '%s\n' "$*"; }
warn() { printf '!! %s\n' "$*" >&2; }
err()  { printf 'XX %s\n' "$*" >&2; }
rule() { printf -- '-----------------------------------------------------------\n'; }

# ---------------------------------------------------------------------------
# git helpers
# ---------------------------------------------------------------------------

# echo a local ref (branch, origin/branch, ...) that resolves, else nothing
resolve_ref() {
	if git rev-parse --verify --quiet "refs/heads/$1" >/dev/null 2>&1; then
		printf '%s\n' "$1"
	elif git rev-parse --verify --quiet "refs/remotes/origin/$1" >/dev/null 2>&1; then
		printf '%s\n' "origin/$1"
	fi
	return 0
}

ref_exists() { git rev-parse --verify --quiet "$1^{commit}" >/dev/null 2>&1; }

# count matching records in a classification file (0 when none)
count_matching() {
	cm_n=`grep -c -- "$1" "$2" 2>/dev/null`
	[ -n "$cm_n" ] || cm_n=0
	printf '%s\n' "$cm_n"
}

# ---------------------------------------------------------------------------
# classify_repo <cur> <arg> <merged> <output-file>
#
# Writes one record per file to <output-file>:
#
#     <state>|<by>|<path>|<detail>
#
#   state  : added | deleted | modified
#   by     : ARG | CUR | BOTH
#   detail : for 'modified' files, one of
#              both-merged  - both sides' changes are in the result
#              kept-CUR     - the merge ended up with the CURRENT version
#              kept-ARG     - the merge ended up with the ARGUMENT version
#            so a merge that silently preferred one side over the other is
#            visible instead of looking like a normal merge.
# ---------------------------------------------------------------------------
classify_repo() {
	cl_cur=$1; cl_arg=$2; cl_merged=$3; cl_out=$4

	: > "$cl_out"
	: > "$cl_out.cand"
	ref_exists "$cl_cur"    || return 0
	ref_exists "$cl_arg"    || return 0
	ref_exists "$cl_merged" || return 0

	{ git diff --name-only "$cl_cur" "$cl_merged"
	  git diff --name-only "$cl_arg" "$cl_merged"
	  git diff --name-only "$cl_cur" "$cl_arg"; } 2>/dev/null \
		| sort -u > "$cl_out.cand"

	while IFS= read -r cl_f; do
		[ -n "$cl_f" ] || continue

		cl_in_cur=N; cl_in_arg=N; cl_in_mrg=N
		git cat-file -e "$cl_cur:$cl_f" 2>/dev/null && cl_in_cur=Y
		git cat-file -e "$cl_arg:$cl_f" 2>/dev/null && cl_in_arg=Y
		git cat-file -e "$cl_merged:$cl_f" 2>/dev/null && cl_in_mrg=Y

		if [ "$cl_in_mrg" = N ]; then
			if   [ "$cl_in_cur" = Y ] && [ "$cl_in_arg" = Y ]; then
				printf 'deleted|BOTH|%s|%s\n' "$cl_f" gone >> "$cl_out"
			elif [ "$cl_in_cur" = Y ]; then
				printf 'deleted|ARG|%s|%s\n'  "$cl_f" gone >> "$cl_out"
			else
				printf 'deleted|CUR|%s|%s\n'  "$cl_f" gone >> "$cl_out"
			fi
			continue
		fi

		if [ "$cl_in_cur" = N ] && [ "$cl_in_arg" = N ]; then
			printf 'added|BOTH|%s|%s\n' "$cl_f" gone >> "$cl_out"
		elif [ "$cl_in_cur" = N ]; then
			printf 'added|ARG|%s|%s\n' "$cl_f" gone >> "$cl_out"
		elif [ "$cl_in_arg" = N ]; then
			printf 'added|CUR|%s|%s\n' "$cl_f" gone >> "$cl_out"
		else
			cl_b_cur=`git rev-parse "$cl_cur:$cl_f"    2>/dev/null`
			cl_b_arg=`git rev-parse "$cl_arg:$cl_f"    2>/dev/null`
			cl_b_mrg=`git rev-parse "$cl_merged:$cl_f" 2>/dev/null`
			if   [ "$cl_b_cur" = "$cl_b_mrg" ] && [ "$cl_b_arg" = "$cl_b_mrg" ]; then
				continue                    # really unchanged
			elif [ "$cl_b_cur" = "$cl_b_mrg" ]; then
				printf 'modified|BOTH|%s|kept-CUR\n'    "$cl_f" >> "$cl_out"
			elif [ "$cl_b_arg" = "$cl_b_mrg" ]; then
				printf 'modified|BOTH|%s|kept-ARG\n'    "$cl_f" >> "$cl_out"
			else
				printf 'modified|BOTH|%s|both-merged\n' "$cl_f" >> "$cl_out"
			fi
		fi
	done < "$cl_out.cand"

	rm -f "$cl_out.cand"
}

# human readable rendering of a classification file
print_classification() {
	pc_file=$1; pc_arg=$2; pc_cur=$3

	if [ ! -s "$pc_file" ]; then
		say "      (no differences)"
		return 0
	fi

	while IFS='|' read -r pc_state pc_by pc_path pc_detail; do
		[ -n "$pc_state" ] || continue
		case "$pc_by" in
		ARG) pc_who="$pc_arg" ;;
		CUR) pc_who="$pc_cur" ;;
		*)   pc_who="both"   ;;
		esac
		case "$pc_state" in
		added)   pc_label="ADDED by"   ;;
		deleted) pc_label="DELETED by" ;;
		*)       pc_label="MODIFIED"   ;;
		esac
		case "$pc_detail" in
		kept-CUR)    pc_note=' <- current branch version won'    ;;
		kept-ARG)    pc_note=' <- argument branch version won'   ;;
		both-merged) pc_note=' <- both changes merged'           ;;
		*)           pc_note=''                                   ;;
		esac
		printf '      %-11s %-22s %s%s\n' "$pc_label" "$pc_who" "$pc_path" "$pc_note"
	done < "$pc_file"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
	case "$1" in
	--pull)    OPT_PULL=1; shift ;;
	--dry-run) OPT_DRY=1;  shift ;;
	--force)   OPT_FORCE=1; shift ;;
	-h|--help) usage; exit 0 ;;
	-*)        err "unknown option '$1'"; usage; exit 1 ;;
	*)         break ;;
	esac
done

if [ $# -lt 1 ]; then
	err "no branch supplied"
	usage
	exit 1
fi

if [ "$OPT_PULL" = 1 ]; then
	rm -f /root/systempull.sh
	cp /TopStor/systempull.sh /root/ 2>/dev/null
fi

if [ "$OPT_DRY" = 1 ]; then
	# a dry run must not touch the real manifest
	MERGE_MANIFEST=`mktemp /tmp/.systemmerge_dryrun.XXXXXX` || exit 1
fi

: > "$MERGE_MANIFEST"
{
	printf '# systemmerge.sh manifest - written %s\n' "`date`"
	printf '# consumed by systemgetdiff.sh - do not edit\n'
} >> "$MERGE_MANIFEST"

for mo_arg in "$@"; do
	if [ -z "$mo_arg" ]; then
		err "empty branch name - skipped"
		RC_OVERALL=1
		continue
	fi

	printf '\n'
	printf '===========================================================\n'
	printf ' merging  %s  into  the branch each repository is on\n' "$mo_arg"
	printf '===========================================================\n'

	for mo_repo in $REPOS; do
		mo_path="$ROOT/$mo_repo"
		[ -d "$mo_path" ] || continue

		cd "$mo_path" 2>/dev/null || continue
		git rev-parse --git-dir >/dev/null 2>&1 || continue

		if [ "$OPT_PULL" = 1 ]; then
			/root/systempull.sh "$mo_arg" >/dev/null 2>&1
			cd "$mo_path" 2>/dev/null || continue
		fi

		say ""
		rule; say "##  $mo_path"; rule

		# --- this repository's OWN current branch -----------------------
		mo_cur=`git rev-parse --abbrev-ref HEAD 2>/dev/null`
		if [ -z "$mo_cur" ] || [ "$mo_cur" = HEAD ]; then
			err "$mo_path has a detached HEAD - skipped"
			RC_OVERALL=1
			continue
		fi
		say "current branch          : $mo_cur"

		# --- never stack on an unfinished merge -------------------------
		if [ -f "`git rev-parse --git-dir`/MERGE_HEAD" ]; then
			err "a merge is ALREADY in progress here - skipped"
			say  "   continue it:  cd $mo_path && git merge --continue"
			say  "   or discard it:  cd $mo_path && git merge --abort"
			printf 'repo=%s path=%s current=%s arg=%s merged=%s status=in-progress\n' \
				"$mo_repo" "$mo_path" "$mo_cur" "$mo_arg" \
				"${mo_arg}_${mo_cur}" >> "$MERGE_MANIFEST"
			RC_OVERALL=2
			continue
		fi

		# --- does the argument branch exist HERE? -----------------------
		mo_argref=`resolve_ref "$mo_arg"`
		if [ -z "$mo_argref" ]; then
			warn "branch '$mo_arg' does not exist in $mo_repo - skipped"
			say  "   the three repositories do not always carry the same branches"
			printf 'repo=%s path=%s current=%s arg=%s merged=%s status=no-such-branch\n' \
				"$mo_repo" "$mo_path" "$mo_cur" "$mo_arg" \
				"${mo_arg}_${mo_cur}" >> "$MERGE_MANIFEST"
			RC_OVERALL=1
			continue
		fi
		say "argument branch         : $mo_arg  ->  $mo_argref"

		# --- refuse a merge that cannot do anything ---------------------
		# git would print "Already up to date." and leave you with an empty
		# difference that still looks like a successful merge.  That is the
		# quietest way for this script to "prefer one commit over the other".
		if [ "$OPT_FORCE" = 0 ] && git merge-base --is-ancestor "$mo_argref" HEAD 2>/dev/null; then
			warn "'$mo_arg' is ALREADY merged into '$mo_cur' in $mo_repo - skipped"
			say  "   merging it again would produce no change at all."
			say  "   if you meant to merge into a different branch, check that one"
			say  "   out first:  cd $mo_path && git checkout <branch>"
			say  "   to override anyway:  systemmerge.sh --force $mo_arg"
			printf 'repo=%s path=%s current=%s arg=%s merged=%s status=already-merged\n' \
				"$mo_repo" "$mo_path" "$mo_cur" "$mo_argref" "$mo_merged" >> "$MERGE_MANIFEST"
			RC_OVERALL=1
			continue
		fi

		# --- dry run stops here ----------------------------------------
		if [ "$OPT_DRY" = 1 ]; then
			say "DRY RUN                : would create and merge into ${mo_arg}_${mo_cur}"
			continue
		fi

		# --- stash tracked edits so they cannot leak into the merge -----
		mo_stashed=0
		mo_stashname="systemmerge-$(date +%Y%m%d-%H%M%S)-$mo_repo"
		if [ -n "`git status --porcelain --untracked-files=no`" ]; then
			if git stash push --quiet -m "$mo_stashname" >/dev/null 2>&1; then
				mo_stashed=1
				say "local changes          : stashed as '$mo_stashname'"
			else
				err "cannot stash local changes - skipped to protect your work"
				RC_OVERALL=1
				continue
			fi
		else
			say "local changes          : none"
		fi

		# --- refresh: fast-forward only, never discards local commits ---
		git fetch --prune --quiet origin >/dev/null 2>&1
		if ref_exists "origin/$mo_cur"; then
			if git merge --ff-only --quiet "origin/$mo_cur" >/dev/null 2>&1; then
				say "refreshed              : fast-forwarded $mo_cur to origin/$mo_cur"
			else
				say "refreshed              : $mo_cur has local commits, kept as they are"
			fi
		fi
		mo_cur=`git rev-parse --abbrev-ref HEAD`
		mo_merged="${mo_arg}_${mo_cur}"

		# --- create the merge branch from the current tip ---------------
		if ref_exists "$mo_merged"; then
			say "note                   : $mo_merged existed, it is being reset onto $mo_cur"
		fi
		if ! git checkout -q -B "$mo_merged" "$mo_cur"; then
			err "could not create $mo_merged - skipped"
			[ "$mo_stashed" = 1 ] && git stash pop --quiet >/dev/null 2>&1
			RC_OVERALL=1
			continue
		fi

		# --- THE MERGE --------------------------------------------------
		# --no-ff keeps both parents in the history, and unlike the old
		# script the exit status is actually inspected.
		mo_log="/tmp/.smmerge.$$.$mo_repo"
		git merge --no-ff --no-edit "$mo_argref" -m "merge $mo_arg into $mo_cur" >"$mo_log" 2>&1
		mo_rc=$?

		if [ "$mo_rc" -ne 0 ]; then
			rule
			err "MERGE FAILED in $mo_path (git merge exit status $mo_rc)"
			sed 's/^/   /' "$mo_log" 2>/dev/null
			rule
			say "files still in conflict:"
			git diff --name-only --diff-filter=U 2>/dev/null | sed 's/^/   /'
			rule
			say "the conflict markers are still in the work tree, on purpose."
			say "  inspect :  cd $mo_path && git status"
			say "  resolve :  edit the files, then  git add -A && git commit"
			say "  discard :  cd $mo_path && git merge --abort"
			say "DO NOT run systempush.sh while this is unresolved - it would publish"
			say "the conflict markers onto the shared branch."
			rm -f "$mo_log"
			printf 'repo=%s path=%s current=%s arg=%s merged=%s status=conflict\n' \
				"$mo_repo" "$mo_path" "$mo_cur" "$mo_argref" "$mo_merged" >> "$MERGE_MANIFEST"
			RC_OVERALL=2
			continue
		fi
		sed 's/^/   /' "$mo_log" 2>/dev/null
		rm -f "$mo_log"

		# --- did the merge really keep both sides? -----------------------
		say "merge result           : clean, $mo_merged is now checked out"
		if git merge-base --is-ancestor "$mo_argref" HEAD 2>/dev/null; then
			say "  argument side present : yes"
		else
			warn "  argument side present : NO - git considers '$mo_arg' already merged,"
			say  "     so the argument branch contributed NOTHING to this merge."
		fi
		if git merge-base --is-ancestor "$mo_cur" HEAD 2>/dev/null; then
			say "  current side present  : yes"
		else
			warn "  current side present  : NO - the current branch was dropped"
		fi

		# --- what did each side actually contribute? ---------------------
		mo_class="/tmp/.smclass.$$.$mo_repo"
		classify_repo "$mo_cur" "$mo_argref" "$mo_merged" "$mo_class"
		say ""
		say "  what each side contributed in $mo_repo:"
		print_classification "$mo_class" "$mo_arg" "$mo_cur"

		mo_pref=`count_matching 'kept-CUR' "$mo_class"`
		mo_prea=`count_matching 'kept-ARG' "$mo_class"`
		if [ "$mo_pref" -gt 0 ]; then
			warn "  $mo_pref file(s): the merge kept the CURRENT version, the argument lost:"
			grep 'kept-CUR' "$mo_class" | cut -d'|' -f3 | sed 's/^/     /'
		fi
		if [ "$mo_prea" -gt 0 ]; then
			warn "  $mo_prea file(s): the merge kept the ARGUMENT version, the current branch lost:"
			grep 'kept-ARG' "$mo_class" | cut -d'|' -f3 | sed 's/^/     /'
		fi
		rm -f "$mo_class"

		{
			printf 'repo=%s path=%s current=%s arg=%s merged=%s status=clean' \
				"$mo_repo" "$mo_path" "$mo_cur" "$mo_argref" "$mo_merged"
			[ "$mo_stashed" = 1 ] && printf ' stashed=%s' "$mo_stashname"
			printf '\n'
		} >> "$MERGE_MANIFEST"

		if [ "$mo_stashed" = 1 ]; then
			say ""
			say "  your earlier local changes are still stashed ('$mo_stashname') -"
			say "  bring them back with:  cd $mo_path && git stash pop"
		fi
	done
done

cd "${ROOT:-/}/TopStor" 2>/dev/null

if [ "$OPT_DRY" = 1 ]; then
	rm -f "$MERGE_MANIFEST"
	printf '\n(dry run - nothing was changed)\n'
	exit $RC_OVERALL
fi

printf '\n===========================================================\n'
printf ' manifest  : %s\n' "$MERGE_MANIFEST"
printf ' review it with:\n'
printf '   systemgetdiff.sh\n'
printf '===========================================================\n'

if [ "$RC_OVERALL" = 0 ]; then
	say ""
	say "All repositories merged cleanly. Nothing has been pushed anywhere yet."
	say "Review the result with  systemgetdiff.sh  before you push."
else
	say ""
	err "at least one repository did not merge cleanly - read the messages above."
	err "DO NOT run systempush.sh until every conflict is resolved."
fi

exit $RC_OVERALL
