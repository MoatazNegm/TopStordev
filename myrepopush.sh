#!/usr/bin/sh
fnupdate () {
	#git reset --hard
	git add --all
	git rm -rf __py*
	#git commit -am 'fixing' --allow-empty
	#git checkout -b $1
	git checkout  $1
	echo git push myrepo $1 -u --force
	git push myrepo $1 -u --force
	if [ $? -ne 0 ];
	then
		fold=`pwd | awk -F'/' '{print $NF'`
		echo something went wrong while updating $1 in directory $job .... consult the devleloper
		git remote remove myrepo
		cd /TopStor
		exit
	fi
	sync
	sync
	sync
}

cd /TopStor/
. /TopStor/myrepolib.sh
branch=`echo $@ | awk '{print $1}'`
cjobs=(`echo TopStor_TopStordev pace_HC topstorweb_TopStorweb`)
branchc=`echo $branch | wc -c`
if [ $branchc -le 3 ];
then
	echo no valid branch is supplied .... exiting
	exit
fi 
flag=1
echo branch $branch
chown 33:33 /root/gitrepo/git/*  -R
chown 33:33 /root/gitrepo/git/  -R
myhostip=`docker exec etcdclient /TopStor/etcdgetlocal.py clusternodeip`
echo myhostip=$myhostip
if ! software_ready "$myhostip"; then
	echo "the software container is not ready .... not touching the cluster repos, exiting"
	exit 1
fi
while [ $flag -ne 0 ];
do
	rjobs=(`echo "${cjobs[@]}"`)
	echo rjobs=${rjobs[@]}
	for jobinfo in "${rjobs[@]}";
	do
		echo '###########################################'
		job=`echo $jobinfo | awk -F'_' '{print $1}'`
		gitrepo=`echo $jobinfo | awk -F'_' '{print $2}'`'.git'
		cd /$job
		if ! ensure_bare_repo $gitrepo; then
			echo could not create the git repo $gitrepo .... exiting
			exit 1
		fi
		repoloc=${myhostip}'/git/'$gitrepo
		if ! git remote -v | grep -q $repoloc; then
			git remote remove myrepo 2>/dev/null
			echo git remote add myrepo http://${myhostip}/git/$gitrepo
			git remote add myrepo http://${myhostip}/git/$gitrepo
		fi
		if ! git ls-remote myrepo >/dev/null 2>&1; then
			echo the repo $gitrepo is not served at http://${myhostip}/git/$gitrepo .... exiting
			exit 1
		fi
 		echo $job
		cd /$job
		if [ $? -ne 0 ];
		then
			echo the directory $job is not found... exiting
			exit
		fi
		fnupdate $branch 
		echo hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh
		cjobs=(`echo "${cjobs[@]}" | sed "s/$jobinfo//g" `)
  	done
	lencjobs=`echo $cjobs | wc -c`
	if [ $lencjobs -le 3 ];
	then
		flag=0
	fi
done
cd /TopStor
myhost=`docker exec etcdclient /TopStor/etcdgetlocal.py clusternode`
leaderip=`docker exec etcdclient /TopStor/etcdgetlocal.py leaderip`
stamp=`date +%s`
cd /topstorweb
git show | grep commit
cd /pace
git show | grep commit
cd /TopStor
git show | grep commit
echo finished
