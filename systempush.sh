#!/usr/bin/sh
fnupdate () {
	#git reset --hard
	git add --all
	git rm -rf __py*
	git commit -am 'fixing' --allow-empty
	git checkout -b $1
	git checkout  $1
	git push origin $1
	if [ $? -ne 0 ];
	then
		fold=`pwd | awk -F'/' '{print $NF'`
		echo something went wrong while updating $1 in directory $fold.... consult the devleloper
		exit
	fi
	sync
	sync
	sync
}

cd /TopStor/
branch=`echo $@ | awk '{print $1}'`
cjobs=(`echo TopStor pace topstorweb`)
branchc=`echo $branch | wc -c`
if [ $branchc -le 3 ];
then
	echo no valid branch is supplied .... exiting
	exit
fi 
flag=1
echo branch $branch
while [ $flag -ne 0 ];
do
	rjobs=(`echo "${cjobs[@]}"`)
	echo rjobs=${rjobs[@]}
	for job in "${rjobs[@]}";
	do
		echo '###########################################'
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
cd /TopStor
myhost=`docker exec etcdclient /TopStor/etcdgetlocal.py clusternode`
leaderip=`docker exec etcdclient /TopStor/etcdgetlocal.py leaderip`
stamp=`date +%s`
/TopStor/etcddel.py $leaderip sync/cversion --prefix
/TopStor/etcdput.py $leaderip sync/cversion/_${branch}__/request cversion_$stamp
/TopStor/etcdput.py $leaderip sync/cversion/_${branch}__/request/$myhost cversion_$stamp
cd /topstorweb
git show | grep commit
cd /pace
git show | grep commit
cd /TopStor
git show | grep commit
echo finished
