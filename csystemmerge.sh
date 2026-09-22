#!/usr/bin/sh
# /TopStor/csystemmerge.sh
#
# Container-aware variant of systemmerge.sh. Kept separate so the
# original physical-server flow is untouched.
#
# Container-only fix: in a worktree-pinned bind mount, the original
#     git branch -D $1_$currentbranch
#     git checkout -b $1_$currentbranch
#     git merge $1 -m'mergin'$1' on '$3
# fails because the worktree refuses to switch branches.
#
# The original also calls /root/systempull.sh which it builds by
# `rm -rf /root/systempull.sh; cp /TopStor/systempull.sh /root/`.
# In the container, we already have /TopStor/csystempull.sh (the
# container-aware sibling) so we skip the cp step and call it directly.
#
# Container mode also replaces the merge-dance with a non-switching
# variant: `git branch -f $1_$currentbranch HEAD` then a
# `git merge-tree` preview (since the actual merge-commit can't be
# created without checking out the target branch).
#
# Falls through to the original systemmerge.sh behaviour on a real
# physical server (when /.dockerenv is absent).

set +e

if [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then
    ISCONTAINER=1
else
    ISCONTAINER=0
fi

fnupdate () {
	echo '###########################################' $1
	currentbranch=$3
	if [ "$ISCONTAINER" = "1" ]; then
		# Container: don't switch branches in a pinned worktree.
		# Force-move the merge target to current HEAD (no switch),
		# then show what `git merge $1` would produce.
		git branch -f $1_$currentbranch HEAD 2>/dev/null || true
		git merge-tree $1 $1_$currentbranch
	else
		git branch -D $1_$currentbranch
		git checkout -b $1_$currentbranch
		git merge $1 -m'mergin'$1' on '$3
		#if [ $? -ne 0 ];
		#then
#			echo something went wrong while updating $1 .... consult the devleloper
#			exit
#		fi
		echo '------checking differrences in '$2' between the branches '$1' and '$currentbranch'-------------'
		git diff --name-status  $1 $1_$currentbranch
		#git diff -U3 $1_$currentbranch $1
		echo '------end of deifferrences in '$2'  between the branches '$1' and '$currentbranch'-------------'
	fi
	sync
	sync
	sync
}
if [ "$ISCONTAINER" = "1" ]; then
	# Container: call the container-aware sibling directly; no need
	# to copy systempull.sh into /root (which is what the original does).
	cjobs=(`echo TopStor pace topstorweb`)
	branch=$1
	branchc=`echo $branch | wc -c`
	if [ $branchc -le 3 ];
	then
		echo no valid branch is supplied .... exiting
		exit
	fi
	currentbranch=`git branch | grep '*' | awk '{print $NF}' | awk -F'_' '{print $1}'`
	echo $branch | grep samebranch
	if [ $? -eq 0 ];
	then
		branch=`git branch | grep '*' | awk '{print $2}'`
	fi

	/TopStor/csystempull.sh $branch
	/TopStor/csystempull.sh $currentbranch
else
	rm -rf /root/systempull.sh
	cp /TopStor/systempull.sh /root/
	cjobs=(`echo TopStor pace topstorweb`)
	branch=$1
	branchc=`echo $branch | wc -c`
	if [ $branchc -le 3 ];
	then
		echo no valid branch is supplied .... exiting
		exit
	fi
	currentbranch=`git branch | grep '*' | awk '{print $NF}' | awk -F'_' '{print $1}'`
	echo $branch | grep samebranch
	if [ $? -eq 0 ];
	then
		branch=`git branch | grep '*' | awk '{print $2}'`
	fi

	/root/systempull.sh $branch
	/root/systempull.sh $currentbranch
fi
echo .............................................................................
echo start mergin
flag=1
while [ $flag -ne 0 ];
do
	rjobs=(`echo "${cjobs[@]}"`)
	echo rjobs=${rjobs[@]}
	for job in "${rjobs[@]}";
	do
 		echo $job
		cd /$job
		if [ $? -ne 0 ];
		then
			echo the directory $job is not found... exiting
			exit
		fi
		fnupdate $branch $job $currentbranch
		cjobs=(`echo "${cjobs[@]}" | sed "s/$job//g" `)
  	done
	lencjobs=`echo $cjobs | wc -c`
	if [ $lencjobs -le 3 ];
	then
		flag=0
	fi
done
cd /TopStor
echo Please note that nothing was committed. so you must systempush the new branch name after you review the merge status
echo finished
