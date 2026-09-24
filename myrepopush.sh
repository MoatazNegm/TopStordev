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
# Guard: myhostip must be a valid IPv4 address. Without this check, the
# later `cd /root/gitrepo/git/$gitrepo` fails silently under `set +e`,
# and the subsequent `rm -rf *` and `git init --bare` run in the wrong
# cwd, destroying the working tree of whichever repo the loop processes
# first. (See csystempull.sh incident Sep 24 2026.)
echo "$myhostip" | grep -Eq '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
if [ $? -ne 0 ]; then
	echo "myrepopush: myhostip '$myhostip' is empty or not a valid IPv4 address; exiting"
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
	        repoloc=${myhostip}'/git/'$gitrepo
		git remote -v | grep $repoloc 
		if [ $? -ne 0 ];
		then
			cd /$job
			git remote remove myrepo
			echo git remote add myrepo http://${myhostip}/git/$gitrepo
			git remote add myrepo http://${myhostip}/git/$gitrepo
			cd /root/gitrepo/git/$gitrepo
			rm -rf *
			git init --bare
			cd ..
			echo chown 33:33 /root/gitrepo/git/$gitrepo -R
			chown 33:33 /root/gitrepo/git/$gitrepo -R
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
