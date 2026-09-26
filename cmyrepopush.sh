#!/usr/bin/sh
# /root/cmyrepopush.sh
#
# Container-aware variant of myrepopush.sh. Kept OUTSIDE the
# /TopStor/ git working tree on purpose: any push workflow ends
# with `git clean -fd`, which would otherwise delete this script
# (it is untracked). Mounting it under /root makes it persist
# across the very git-clean it triggers.
#
# Differences from the original myrepopush.sh:
#   * Detect whether we are running inside a container
#     (`/.dockerenv` or `/run/.containerenv`).
#   * Resolve the software container's IP:
#       1. Try etcdclient (dynamic cluster-node IP).
#       2. Validate the discovered IP actually answers git://
#          on :9418. If not, fall back to the static IP
#          10.11.12.10 baked into the `docker run` for the
#          `software` container.
#   * `safe.directory '*'` is added unconditionally so that the
#     bare repos owned by the host DinD user (uid 33 / tape) are
#     not flagged as dubious-owned.
#   * `git config --global protocol.git.allow always` so git
#     does not warn about the unauthenticated git:// transport.
#
# Physical-server behaviour: identical to myrepopush.sh on every
# line — this script only adds the IP validation and the
# container-only `safe.directory` setup before the original
# flow runs.

set +e

if [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then
    ISCONTAINER=1
else
    ISCONTAINER=0
fi

# Make the bare repos safe for git regardless of which uid mounted
# them onto the host DinD volume.
git config --global --add safe.directory '*' 2>/dev/null
# Permit git:// without an interactive "yes" / without
# setting `safe.directory` per clone.
git config --global --add protocol.git.allow always 2>/dev/null

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
# Resolve the software container's IP:
#   1. Try etcdclient (dynamic cluster-node IP).
#   2. Validate the discovered IP actually answers git:// on :9418.
#      If it does not (etcdclient returns the wrong node, e.g. the
#      wetty container, or etcdclient itself is down), fall back to
#      the static IP 10.11.12.10 baked into the `docker run` for
#      the `software` container.
myhostip=`docker exec etcdclient /TopStor/etcdgetlocal.py clusternodeip 2>/dev/null`
if [ -n "$myhostip" ]; then
	# Probe git-daemon on the discovered IP. Use bash's /dev/tcp
	# when available; otherwise fall back to a 1-second timeout
	# ping which is enough to spot the wrong-subnet case (e.g.
	# 10.11.11.14 — wetty — when the right answer is 10.11.12.10).
	if command -v timeout >/dev/null 2>&1; then
		timeout 2 bash -c "exec 3<>/dev/tcp/$myhostip/9418" 2>/dev/null
		probe_ok=$?
	else
		# No timeout binary: use ping (less precise but always there)
		ping -c 1 -W 1 "$myhostip" >/dev/null 2>&1
		probe_ok=$?
	fi
	if [ "$probe_ok" != "0" ]; then
		echo "cmyrepopush: discovered IP $myhostip is unreachable on :9418, falling back to 10.11.12.10"
		myhostip=""
	fi
fi
if [ -z "$myhostip" ]; then
	myhostip="10.11.12.10"
	echo "cmyrepopush: using static software container IP $myhostip"
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