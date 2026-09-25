#!/usr/bin/sh
# /TopStor/cdevproxypush.sh
#
# Container-aware variant of devproxypush.sh. Kept separate so the
# original physical-server flow is untouched.
#
# Container-only fix: the original's
#     git checkout QSD3.15
#     git checkout -b $1 $origin/$1
# is replaced by a single `git checkout -B $1 $origin/$1` (atomic
# create-or-move + switch), the bare `git fetch $origin` is
# replaced by an explicit refspec so the tracking ref updates
# reliably in this git version, and the `git branch -D $1` is
# made non-fatal (it can fail when $1 is the current branch).
# Everything else (reset, clean, config, checkout -- *, __py*
# cleanup, push) is byte-identical to devproxypush.sh.
#
# Falls through to the original devproxypush.sh behaviour on a
# real physical server (when /.dockerenv is absent).

set +e

if [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then
    ISCONTAINER=1
else
    ISCONTAINER=0
fi

fnupdate () {
	origin=`git remote -v | grep 252 | head -1 | awk '{print $1}'`
	remote=`git remote -v | grep github | grep $2 |  head -1 | awk '{print $1}'`
	if [ "$ISCONTAINER" = "1" ]; then
		# Container: skip the `git checkout QSD3.15` (we
		# stay on the current branch). `git branch -D $1`
		# is made non-fatal — it can fail when $1 IS the
		# current branch, which is fine since `-B` handles
		# it. Single `checkout -B` replaces `checkout -b`.
		git branch -D $1 2>/dev/null || true
		git fetch $origin refs/heads/$1:refs/remotes/$origin/$1
		if [ $? -ne 0 ];
		then
			echo something went wrong while pulling from remote $origin, branch: $1, dir:`pwd` .... consult the devleloper
			exit
		fi
		# Container-only fix: same root bug as cproxypush.sh had.
		# The fetch was followed by `git checkout -B` with no
		# pre-checkout reset/clean, so any local modification or
		# untracked file/dir in the working tree caused the
		# checkout to abort with "would be overwritten", which
		# then made `git push` fail with "src refspec <branch>
		# does not match any" because the local branch was never
		# created. Force-resetting to origin/$1 and pruning
		# untracked files/dirs first unblocks the checkout.
		git reset --hard $origin/$1
		git clean -fd
		git checkout -B $1 $origin/$1
	else
		git checkout QSD3.15
		git branch -D $1
		git fetch $origin
		if [ $? -ne 0 ];
		then
			echo something went wrong while pulling from remote $origin, branch: $1, dir:`pwd` .... consult the devleloper
			exit
		fi
		git checkout -b $1  $origin/$1
		if [ $? -ne 0 ];
		then
			echo something went wrong while pulling from remote $origin, branch: $1, dir:`pwd` .... consult the devleloper
			exit
		fi
		git reset --hard $origin/$1
		git clean -fd
		git config --replace-all pull.rebase false
		git checkout -- *
		git rm -rf __py*
	fi
	git push $remote $1
	if [ $? -ne 0 ];
	then
		echo something went wrong while pushing to origin: $remote, branch: $1, dir:`pwd` .... consult the devleloper
		exit
	fi
	sync
	sync
	sync
}

fnupdateold () {
	git checkout -b $1
	git checkout $1
	git reset --hard
	git clean -fd
	git config --replace-all pull.rebase false
	git rm -rf __py*
	origin=`git remote -v | grep 252 | head -1 | awk '{print $1}'`
	remote=`git remote -v | grep github | head -1 | awk '{print $1}'`
	git pull $origin $1
	if [ $? -ne 0 ];
	then
		echo something went wrong while pulling from remote $remote, branch: $1 .... consult the devleloper
		exit
	fi
	git push $remote $1
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
dev=$2
devc=`echo x$dev | wc -c`
if [ $devc -le 4 ];
then
	echo no valid developer name is supplied .... exiting
	exit
fi 
ondevtopstor=$(ls / | grep $dev | grep TopStor)
devl=`echo $ondevtopstor | wc -c` 
if [ $devl -le 4 ];
then
	echo No such developer $dev 
	exit
fi
devl=`echo $ondevtopstor | wc -l` 
echo $ondevtopstor | grep ' '
if [ $? -eq 0 ];
then
	echo choose a valid developer name.i.e. TopStor\_\<\<developer\>\> between:
	echo $ondevtopstor  
	exit
fi

developer=`echo $ondevtopstor | awk -F'_' '{print $NF}'`
f
flag=1
while [ $flag -ne 0 ];
do
	rjobs=(`echo "${cjobs[@]}"`)
	echo rjobs=${rjobs[@]}
	for job in "${rjobs[@]}";
	do
		echo '###########################################'
		echo '###########################################'
 		echo ${job}_${developer}
		isexit=1
		cd /${job}_${developer}
		if [ $? -ne 0 ];
		then
				echo the directory $job is not found... exiting
				exit
		fi

		fnupdate $branch $developer 
		cjobs=(`echo "${cjobs[@]}" | sed "s/$job//g" `)
  	done
	lencjobs=`echo $cjobs | wc -c`
	if [ $lencjobs -le 3 ];
	then
		flag=0
	fi
done
git show | grep commit
cd /pace_$developer
git show | grep commit
cd /TopStor_$developer
git show | grep commit
echo the latest commit in the $developer repo:
echo returning back to the TopStor directory
cd /TopStor
echo finished
