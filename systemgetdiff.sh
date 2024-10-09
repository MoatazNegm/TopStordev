#!/usr/bin/sh
currentbranch=`git branch | grep '*' | awk '{print $2}'`
echo $currentbranch | grep _
if [ $? -ne 0 ];
then
	echo Not a merged branch ..it should be having the name RunningBranch_ToTestbranch	
	exit
fi
runbranch=`echo $currentbranch | awk -F'_' '{print $1}'`
git diff -U3 $currentbranch $runbranch
