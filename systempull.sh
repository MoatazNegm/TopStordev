#!/usr/bin/sh
fnupdate () {
	rm -rf pre_apply.sh	
	echo '###########################################' $1
	git fetch origin $1
	if [ $? -ne 0 ];
	then
		echo something went wrong while updating $1 .... consult the devleloper
		exit
	fi
	git branch -D tempb
	git checkout -- *
	git rm -rf __py*
	rm -rf __py*
	git checkout -b tempb
	git branch -D $1
	git checkout -b $1 origin/$1
	git reset --hard
	git checkout -- *
	git rm -rf __py*
	rm -rf __py*
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
echo $branch | grep samebranch
if [ $? -eq 0 ];
then
	branch=`git branch | grep '*' | awk '{print $2}'`
fi
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
		fnupdate $branch 
		cjobs=(`echo "${cjobs[@]}" | sed "s/$job//g" `)
  	done
	lencjobs=`echo $cjobs | wc -c`
	if [ $lencjobs -le 3 ];
	then
		flag=0
	fi
done
docker ps 2>/dev/null | grep software
if [ $? -eq 0 ];
then
	echo running any needed scripts
	leaderip=`docker exec etcdclient /TopStor/etcdgetlocal.py leaderip`
	leader=`docker exec etcdclient /TopStor/etcdgetlocal.py leader`
	myhost=`docker exec etcdclient /TopStor/etcdgetlocal.py clusternode`
	stamp=`date +%s`
	/TopStor/etcddel.py $leaderip sync/cversion --prefix
	/TopStor/etcdput.py $leaderip sync/cversion/_${branch}__/request cversion_$stamp
	/TopStor/etcdput.py $leaderip sync/cversion/_${branch}__/request/$myhost cversion_$stamp
	/TopStor/getcversion.sh $leaderip $leader $myhost
	cd /TopStor
	commit=`git show --abbrev-commit | grep commit | head -1 | awk '{print $2}'`
	echo /TopStor/etcdput.py $leaderip cversion/$myhost $branch-$commit
	/TopStor/etcdput.py $leaderip cversion/$myhost $branch-$commit
	echo $leader | grep $myhost
	if [ $? -ne 0 ];
	then
		myhostip=`docker exec etcdclient /TopStor/etcdgetlocal.py clusternodeip`
		echo ip=$myhostip
		/TopStor/etcdput.py $myhostip cversion/$myhost $branch-$commit
	fi
	/TopStor/myrepopush.sh $branch
fi
/TopStor/pre_apply.sh	
cd /topstorweb
git show | grep commit
cd /pace
git show | grep commit
cd /TopStor
git show | grep commit
echo finished
