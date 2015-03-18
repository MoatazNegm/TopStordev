#!/usr/local/bin/zsh
#cd /root/scripts
gitloc=`echo $@ | awk '{print $1}'`;
filever=`echo $@ | awk '{print $2}'`;
cd $gitloc 
edite=`git diff --name-only master`
echo $filever > ver
tar -cvf /TopStor_${filever}_.tar ver
echo $edite
for n in `echo $edite`
do
#cp "$n" /test/
tar -uvf /TopStor_${filever}_.tar $n  > /dev/null 2>&1
done
gzip /TopStor_${filever}_.tar
#################### encription ###################
openssl  smime  -encrypt -aes256  -in /TopStor_${filever}_.tar.gz  -binary  -outform DEM  -out  /TopStor_${filever}_.tar.gz.enc  code2.pub
rm /TopStor_${filever}_.tar.gz
