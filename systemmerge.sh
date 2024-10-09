#!/usr/bin/sh
fnupdate () {
	echo '###########################################' $1
	currentbranch=$3
	git branch -D $1_$currentbranch
	git checkout -b $1_$currentbranch
	git merge $1 -m'mergin'$1' on '$3
	#if [ $? -ne 0 ];
	#then
#		echo something went wrong while updating $1 .... consult the devleloper
#		exit
#	fi
	echo '------checking differrences in '$2' between the branches '$1' and '$currentbranch'-------------'
	git diff --name-status  $1 $1_$currentbranch 
	#git diff -U3 $1_$currentbranch $1 
	echo '------end of deifferrences in '$2'  between the branches '$1' and '$currentbranch'-------------'
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
currentbranch=`git branch | grep '*' | awk '{print $NF}' | awk -F'_' '{print $1}'`
echo $branch | grep samebranch
if [ $? -eq 0 ];
then
	branch=`git branch | grep '*' | awk '{print $2}'`
fi
/TopStor/systempull.sh $branch
/TopStor/systempull.sh $currentbranch
echo .............................................................................
echo start mergin
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
		fnupdate $branch $job $currentbranch
		cjobs=(`echo "${cjobs[@]}" | sed "s/$job//g" `)
  	done
	lencjobs=`echo $cjobs | wc -c`
	if [ $lencjobs -le 3 ];
	then
		flag=0
	fi
done
cd /TopStor
echo Please note that nothing was committed. so you must systempush the new branch name after you review the merge status
echo finished
