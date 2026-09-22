#!/usr/bin/sh
# /TopStor/cproxyupdate.sh
#
# Container-aware variant of proxyupdate.sh. Kept separate so the
# original physical-server flow is untouched.
#
# Container-only fix: in a worktree-pinned bind mount, the original
#     git branch -D tempb
#     git checkout -b tempb
#     git branch -D $1
#     git checkout -b $1 $remote/$1
#     git reset --hard
#     git checkout -- *
#     git rm -rf __py*
# fails because the worktree refuses to switch branches and the
# reset/checkout/rm would corrupt the pinned working tree.
#
# We replace that whole block with:
#     git fetch $remote refs/heads/$1:refs/remotes/$remote/$1
#     git branch -f $1 $remote/$1 2>/dev/null || true
# which force-creates / force-moves local $1 to the fetched tip
# without touching the worktree's pinned branch.
#
# Falls through to the original proxyupdate.sh behaviour on a real
# physical server (when /.dockerenv is absent).

set +e

if [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then
    ISCONTAINER=1
else
    ISCONTAINER=0
fi

fnupdate () {
	origin=`git remote -v | grep 252 | head -1 | awk '{print $1}'`
	remote=`git remote -v | grep github | grep -v devremote | head -1 | awk '{print $1}'`
	if [ "$ISCONTAINER" = "1" ]; then
		# Container: explicit refspec so tracking ref updates,
		# and force-create/move $1 atomically (don't try to
		# switch branches in a pinned worktree).
		git fetch $remote refs/heads/$1:refs/remotes/$remote/$1
		if [ $? -ne 0 ];
		then
			echo something went wrong while pulling from remote $remote, branch: $1, dir:`pwd` .... consult the devleloper
			exit
		fi
		git branch -f $1 $remote/$1 2>/dev/null || true
	else
		git fetch $remote
		if [ $? -ne 0 ];
		then
			echo something went wrong while pulling from remote $remote, branch: $1, dir:`pwd` .... consult the devleloper
			exit
		fi
		git branch -D tempb
		git clean -f
		git config --replace-all pull.rebase false
		git checkout -- *
		git rm -rf __py*
		git checkout -b tempb
		git branch -D $1
		git checkout -b $1  $remote/$1
		git reset --hard
		git clean -f
		git config --replace-all pull.rebase false
		git checkout -- *
		git rm -rf __py*
	fi
	git push $origin $1
	if [ $? -ne 0 ];
	then
		echo something went wrong while pushing to origin: $origin, branch: $1, dir:`pwd` .... consult the devleloper
		exit
	fi
	sync
	sync
	sync
}
fnupdateold () {
	git add .
	git commit -m 'fixing'
	git checkout -b $1
	git checkout $1
	git reset --hard
	git clean -f
	git config --replace-all pull.rebase false
	git checkout -- *
	git rm -rf __py*
	origin=`git remote -v | grep 252 | head -1 | awk '{print $1}'`
	remote=`git remote -v | grep github | head -1 | awk '{print $1}'`
	git add .
	git commit -m 'fixing'
	git pull $remote $1
	if [ $? -ne 0 ];
	then
		echo something went wrong while pulling from remote $remote, branch: $1 .... consult the devleloper
		exit
	fi
	git push $origin $1
	if [ $? -ne 0 ];
	then
		echo something went wrong while pushing to origin: $origin, branch: $1 .... consult the devleloper
		exit
	fi
	sync
	sync
	sync
}
cjobs=(`echo TopStor pace topstorweb`)
branch=$1
branchc=`echo $branch | wc -c`
if [ $branchc -le 3 ];
then
	echo no valid branch is supplied .... exiting
	exit
fi 
flag=1
while [ $flag -ne 0 ];
do
	rjobs=(`echo "${cjobs[@]}"`)
	echo rjobs=${rjobs[@]}
	for job in "${rjobs[@]}";
	do
		echo '###########################################'
 		echo $job
		isexit=1
		cd /$job
		if [ $? -ne 0 ];
		then
			echo $job | grep topstorweb
			if [ $? -eq 0 ];
			then
				cd /var/www/html/des20/
				if [ $? -eq 0 ];
				then
					isexit=0
				fi
			fi
			if [ $isexit -eq 1 ];
			then
				echo the directory $job is not found... exiting
				exit
			fi
		fi
		fnupdate $branch 
		cjobs=(`echo "${cjobs[@]}" | sed "s/$job//g" `)
  	done
	lencjobs=`echo $cjobs | wc -c`
	if [ $lencjobs -le 3 ];
	then
		flag=0
	fi
done
cd /TopStor
git show | grep commit
echo finished
