#!/usr/bin/sh
fnupdate () {
	git checkout QSD3.15
	git branch -D $1
	origin=`git remote -v | grep 252 | head -1 | awk '{print $1}'`
	remote=`git remote -v | grep github | head -1 | awk '{print $1}'`
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
	git clean -f
	git config --replace-all pull.rebase false
	git checkout -- *
	git rm -rf __py*
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
	git clean -f
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
echo nameserver 8.8.8.8 > /etc/resolv.conf
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
cd /topstorweb
if [ $? -ne 0 ]
then
	cd /var/www/html/des20/
fi
git show | grep commit
cd /pace
git show | grep commit
cd /TopStor
git show | grep commit
echo finished
