#!/usr/local/bin/zsh
traffic=$4
device=$1
date=$2
oper=$3
searchdate1=`./searchdate.sh $device $date $4`
pre=`echo $searchdate1 | awk 'NR==1{printf"%s",$1}'`
post=`echo $searchdate1 | awk 'NR==3{printf"%s",$1}'`
search=`echo $searchdate1 | awk 'NR==2{printf"%s",$1}'`
search1=`echo $search | /usr/local/bin/jq -c '.[]' |awk 'NR==2{printf"%s",$1}'| /usr/local/bin/jq -c '.[]'`
echo $search1 | grep time > /dev/null 2>&1
if [ $? -ne 1 ]
then
search=`echo $search | sed "s/]}/,$oper]}/"`
afteradd=`echo -n $pre ; echo -n $search ; echo $post;`
searchdevice=`./searchdevice.sh $device $4`
pre=`echo $searchdevice | awk 'NR==1{printf"%s",$1}'`
post=`echo $searchdevice | awk 'NR==3{printf"%s",$1}'`
search=`echo $afteradd`
end=`echo -n $pre ; echo -n $search ; echo $post;`
#echo to file
echo $end  
else
search=`echo $search | sed "s/]}/$oper]}/"`
afteradd=`echo -n $pre ; echo -n $search ; echo $post;`
searchdevice=`./searchdevice.sh $device $4`
pre=`echo $searchdevice | awk 'NR==1{printf"%s",$1}'`
post=`echo $searchdevice | awk 'NR==3{printf"%s",$1}'`
search=`echo $afteradd`
end=`echo -n $pre ; echo -n $search ; echo $post;`
#echo to file
echo $end 
fi
