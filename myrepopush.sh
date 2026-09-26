#!/usr/bin/sh
fnupdate () {
	git reset --hard HEAD
	#git add --all
	#git rm -rf __py*
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
cjobs=(`echo TopStor_TopStordev pace_HC topstorweb_TopStorWeb`)
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
# Try etcdclient first (dynamic cluster-node IP); fall back to the static
# software-container IP (10.11.12.10) when etcdclient is not running.
myhostip=`docker exec etcdclient /TopStor/etcdgetlocal.py clusternodeip 2>/dev/null`
if [ -z "$myhostip" ]; then
	myhostip="10.11.12.10"
	echo "myrepopush: etcdclient unreachable, falling back to static software container IP $myhostip"
fi
echo myhostip=$myhostip
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
		repoloc=${myhostip}'/'$gitrepo
		git remote -v | grep $repoloc
		if [ $? -ne 0 ];
		then
			cd /$job
			git remote remove myrepo
			# git:// protocol — matches git-daemon's --base-path=/srv/git in
			# the software container running on $myhostip.
			echo git remote add myrepo git://${myhostip}/$gitrepo
			git remote add myrepo git://${myhostip}/$gitrepo
			# Ensure the bare repo exists on the mirror WITHOUT wiping it.
			# The original script did 'rm -rf *; git init --bare' here,
			# which would have destroyed any branches that had been pushed.
			if [ ! -d /root/gitrepo/git/$gitrepo ]; then
				mkdir -p /root/gitrepo/git
				git init --bare /root/gitrepo/git/$gitrepo
			fi
			# git-daemon-export-ok is required by git-daemon unless
			# --export-all is also given (abdopuppet uses --export-all, but
			# the file is harmless and matches abdopuppet's convention).
			touch /root/gitrepo/git/$gitrepo/git-daemon-export-ok
			# Allow git operations across uid boundaries (the bare repo is
			# owned by the host DinD user; we run as root in the container).
			git config --global --add safe.directory '*'
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
myhost=`docker exec etcdclient /TopStor/etcdgetlocal.py clusternode 2>/dev/null`
leaderip=`docker exec etcdclient /TopStor/etcdgetlocal.py leaderip 2>/dev/null`
stamp=`date +%s`
cd /topstorweb
git show | grep commit
cd /pace
git show | grep commit
cd /TopStor
git show | grep commit
echo finished
