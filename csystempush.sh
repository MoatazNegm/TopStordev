#!/usr/bin/sh
# /TopStor/csystempush.sh
#
# Container-aware variant of systempush.sh. Kept separate so the
# original physical-server flow is untouched.
#
# Container-only fix: the original's
#     git checkout -b $1
#     git checkout  $1
# is replaced by a single `git checkout -B $1` (atomic create-or-move
# + switch). The git-identity safety-net block stays because it's a
# real container-only fix (commit fails silently without it).
# Everything else is byte-identical to systempush.sh.

set +e

if [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then
    ISCONTAINER=1
else
    ISCONTAINER=0
fi

# Container-only safety net: if no git identity is configured, git
# commit fails with "Author identity unknown" and (because this script
# uses `set +e`) the failure is swallowed silently — the local branch
# gets created at the OLD HEAD, the push is a no-op against identical
# origin content, and the script exits 0 even though nothing was
# committed. To make the failure visible we configure a fallback
# identity in the container's ~/.gitconfig if none is set.
if [ "$ISCONTAINER" = "1" ]; then
    if [ -z "$(git config user.name)" ]; then
        git config --global user.name "TopStor Container"
    fi
    if [ -z "$(git config user.email)" ]; then
        git config --global user.email "container@topstor.local"
    fi
fi

fnupdate () {
	#git reset --hard
	git add --all
	git rm -rf __py*
	git commit -am 'fixing' --allow-empty
	if [ "$ISCONTAINER" = "1" ]; then
		# Container: atomic create-or-move + switch. Equivalent
		# to the original's two `git checkout` lines; `-B` also
		# handles the case where $1 already exists locally.
		git checkout -B $1
	else
		git checkout -b $1
		git checkout  $1
	fi
	git push origin $1
	if [ $? -ne 0 ];
	then
		fold=`pwd | awk -F'/' '{print $NF'`
		echo something went wrong while updating $1 in directory $fold.... consult the devleloper
		exit
	fi
	sync
	sync
	sync
}

cd /TopStor/
branch=`echo $@ | awk '{print $1}'`
cjobs=(`echo TopStor pace topstorweb`)
branchc=`echo $branch | wc -c`
if [ $branchc -le 3 ];
then
	echo no valid branch is supplied .... exiting
	exit
fi 
flag=1
echo branch $branch
while [ $flag -ne 0 ];
do
	rjobs=(`echo "${cjobs[@]}"`)
	echo rjobs=${rjobs[@]}
	for job in "${rjobs[@]}";
	do
		echo '###########################################'
 		echo $job
		cd /$job
		if [ $? -ne 0 ];
		then
			echo the directory $job is not found... exiting
			exit
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
docker ps 2>/dev/null | grep software
if [ $? -eq 0 ];
then
	myhost=`docker exec etcdclient /TopStor/etcdgetlocal.py clusternode`
	leaderip=`docker exec etcdclient /TopStor/etcdgetlocal.py leaderip`
	stamp=`date +%s`
	/TopStor/etcddel.py $leaderip sync/cversion --prefix
	/TopStor/etcdput.py $leaderip sync/cversion/_${branch}__/request cversion_$stamp
	/TopStor/etcdput.py $leaderip sync/cversion/_${branch}__/request/$myhost cversion_$stamp
	/TopStor/myrepopush.sh $branch
fi
cd /topstorweb
git show | grep commit
cd /pace
git show | grep commit
cd /TopStor
git show | grep commit
echo finished
