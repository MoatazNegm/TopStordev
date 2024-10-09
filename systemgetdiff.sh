#!/usr/bin/sh
currentbranch=`git branch | grep '*' | awk '{print $2}'`
echo $currentbranch | grep _
if [ $? -ne 0 ];
then
	echo Not a merged branch ..it should be having the name RunningBranch_ToTestbranch	
	exit
fi
runbranch=`echo $currentbranch | awk -F'_' '{print $1}'`
cd /ToStor/
git diff -U3 $runbranch..$currentbranch
cd /pace/
git diff -U3 $runbranch..$currentbranch
cd /topstorweb/
#git diff -U3 $currentbranch..$runbranch
git diff -U3 $runbranch..$currentbranch
cd /TopStor
