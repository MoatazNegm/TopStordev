#!/usr/bin/sh
fnupdate () {
	origin=`git remote -v | grep 252 | head -1 | awk '{print $1}'`
	remote=`git remote -v | grep github | grep  QuickStor |  head -1 | awk '{print $1}'`
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

echo nameserver 8.8.8.8 > /etc/resolv.conf
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
flag=1
while [ $flag -ne 0 ];
do
	rjobs=(`echo "${cjobs[@]}"`)
	echo rjobs=${rjobs[@]}
	for job in "${rjobs[@]}";
	do
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
cd /topstorweb_$developer
if [ $? -ne 0 ]
then
	cd /var/www/html/des20/
fi
git show | grep commit
cd /pace_$developer
git show | grep commit
cd /TopStor_$developer
git show | grep commit
echo the latest commit in the $developer repo:
echo returning back to the TopStor directory
cd /TopStor
echo finished
