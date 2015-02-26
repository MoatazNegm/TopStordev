#!/usr/local/bin/zsh
strstart=$1
strend=$2
file=$3
g=`cat $file | grep $strstart | wc -c`; if [[ g -ge 4 ]];
then 
grepstart=`grep -B99999999 $strstart $file | grep -v $strstart`
grepend=`grep -A99999999 $strend $file | grep -v $strend`
echo $grepstart > $file 
echo $grepend >> $file
else 
echo notfound
fi
###echo $grepend
