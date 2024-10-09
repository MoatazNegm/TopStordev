#!/usr/bin/sh
fnupdate () {
	origin='http://10.11.11.252/git/'$3'.git'
	remote='https://github.com/'$2'/'$1'_mydev.git'
	QuickStor='https://github.com/MoatazNegm/'$3'.git'
	git init
	git remote add origin $origin
	git remote add remote $remote 
	git remote add QuickStor $QuickStor
	git fetch $remote 
	if [ $? -ne 0 ];
	then
		echo something went wrong while fetching for the first time  from remote $remote.. consult the devleloper
		echo However, will continue creating the repos
	fi
	sync
	sync
	sync
}
echo nameserver 8.8.8.8 > /etc/resolv.conf
cjobs=(`echo TopStor pace topstorweb`)
ajobs=(`echo TopStordev HC TopStorweb`)
developer=$1
branchc=`echo $developer | wc -c`
if [ $branchc -le 3 ];
then
	echo no valid developer name is supplied .... exiting
	exit
fi 
for ((i=0; i<${#cjobs[@]}; i++)); do
    		cjob="${cjobs[$i]}"
    		ajob="${ajobs[$i]}"
		echo '###########################################'
 		echo ${cjob}_${developer}
		echo xx$2 | grep init
		if [ $? -eq 0 ];
		then
			echo re-creating the complete ${cjob}_${developer} repo
			rm -rf /${cjob}_${developer}
		fi
		mkdir /${cjob}_${developer}
		cd /${cjob}_${developer}
		if [ $? -ne 0 ];
		then
				echo the directory $cjob is not found... exiting
				exit
		fi
		fnupdate $cjob $developer $ajob
done
cd /TopStor
echo finished
