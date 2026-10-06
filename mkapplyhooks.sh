#!/bin/sh
# mkapplyhooks.sh <branch> [topstor-dir]
# Create the per-branch hook stubs apply.d/<branch>/pre_apply.sh and post_apply.sh (only the ones
# that are missing; an existing hook is never touched).  systempush.sh / csystempush.sh call it for
# every branch they push; systempull.sh / csystempull.sh run the hooks of the branch they pulled.
branch=$1
dir=${2:-.}
if [ -z "$branch" ]; then
	echo "usage: $0 <branch> [topstor-dir]"
	exit 1
fi
d=$dir/apply.d/$branch
mkdir -p "$d" || exit 1
for hook in pre_apply post_apply; do
	f=$d/$hook.sh
	[ -e "$f" ] && continue
	case $hook in
	pre_apply)  when='first, after the cluster sync of the pull' ;;
	post_apply) when='last, after pre_apply' ;;
	esac
	cat > "$f" <<STUB
#!/bin/sh
# $hook hook of branch $branch -- run by systempull.sh / csystempull.sh $when,
# only when this branch was pulled.  Argument 1 = the branch.  Empty on purpose: put here whatever
# this branch needs on a node after a pull (rebuild, migrate, restart ...).  A non-zero exit is reported
# and makes the pull finish "with errors", it does not stop it.
exit 0
STUB
	chmod +x "$f"
done
