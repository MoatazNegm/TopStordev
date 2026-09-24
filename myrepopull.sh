#!/usr/bin/sh
fnupdate () {
	git remote remove leaderrepo
	# git:// protocol — matches git-daemon's --base-path=/srv/git in the
	# software container. $3 is the leader IP (passed by the caller).
	git remote add leaderrepo git://$3/$2
	rm -rf pre_apply.sh	
	echo '###########################################' $1
	git fetch leaderrepo $1
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
	git checkout -b $1 leaderrepo/$1
	git reset --hard
	git checkout -- *
	git rm -rf __py*
	rm -rf __py*
	sync
	sync
	sync
}
cjobs=(`echo TopStor_TopStordev pace_HC topstorweb_TopStorweb`)
branch=$1
leader=`docker exec etcdclient /TopStor/etcdgetlocal.py leader`
leaderlocip=`docker exec etcdclient /TopStor/etcdgetlocal.py ready/$leader`
myhost=`docker exec etcdclient /TopStor/etcdgetlocal.py clusternode`
echo $myhost | grep $leader
if [ $? -eq 0 ];
then
	exit
fi
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
	for jobinfo in "${rjobs[@]}";
	do
		echo '###########################################'
		job=`echo $jobinfo | awk -F'_' '{print $1}'`
		gitrepo=`echo $jobinfo | awk -F'_' '{print $2}'`'.git'
 		echo $job
		cd /$job
		if [ $? -ne 0 ];
		then
			echo the directory $job is not found... exiting
			exit
		fi
		fnupdate $branch $gitrepo $leaderlocip
		cjobs=(`echo "${cjobs[@]}" | sed "s/$jobinfo//g" `)
  	done
	lencjobs=`echo $cjobs | wc -c`
	if [ $lencjobs -le 3 ];
	then
		flag=0
	fi
done
echo running any needed scripts
/TopStor/pre_apply.sh	
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
/TopStor/etcdput.py $leaderip cversion/$myhost $version-$commit
echo $leader | grep $myhost
if [ $? -ne 0 ];
then
	myhost=`docker exec etcdclient /TopStor/etcdgetlocal.py clusternodeip`
	/TopStor/etcdput.py $myhostip cversion/$myhost $version-$commit
fi
/TopStor/getcversion.sh $leaderip $leader $myhost
/TopStor/myrepopush.sh $branch
cd /topstorweb
git show | grep commit
cd /pace
git show | grep commit
cd /TopStor
git show | grep commit

echo finished
