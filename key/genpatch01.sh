#!/usr/local/bin/zsh
#  run as follows: patch <<GIT directory>> <<version number>> 
#cd /root/scripts
here=`pwd`;
gitloc=`echo $@ | awk '{print $1}'`;
filever=`echo $@ | awk '{print $2}'`;
cd $gitloc 
git add --all
currentver=`cat ver`;
msg='preparing currentver ver'$currentver;
git commit -am $msg; 
edite=`git diff --name-only master`
echo $filever > ver
tar -cvf /TopStor_${filever}_.tar ver
echo $currentver > ver;
#echo $edite
cd $here
for n in `echo $edite`
do
#cp "$n" /test/
tar -uvf /TopStor_${filever}_.tar $n  > /dev/null 2>&1
done
gzip /TopStor_${filever}_.tar
#################### encription ###################
openssl  smime  -encrypt -aes256  -in /TopStor_${filever}_.tar.gz  -binary  -outform DEM  -out  /TopStor_${filever}_.tar.gz.enc  code2.pub
rm /TopStor_${filever}_.tar.gz
