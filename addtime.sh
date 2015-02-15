#!/usr/local/bin/zsh
traf=` echo $@ | awk '{print $4}'`;
device=` echo $@ | awk '{print $1}'`;
date=` echo $@ | awk '{print $2}'`;
oper=` echo $@ | awk '{print $3}'`;
searchdate1=`./searchdate.sh $device $date $traf`
pre=`echo $searchdate1 | awk 'NR==1{printf"%s",$1}'`
post=`echo $searchdate1 | awk 'NR==3{printf"%s",$1}'`
search=`echo $searchdate1 | awk 'NR==2{printf"%s",$1}'`
search1=`echo $search | /usr/local/bin/jq -c '.[]' |awk 'NR==2{printf"%s",$1}'| /usr/local/bin/jq -c '.[]'`
echo $search1 | grep time > /dev/null 2>&1
if [ $? -ne 1 ]
then
search=`echo $search | sed "s/]}/,$oper]}/"`
afteradd=`echo -n $pre ; echo -n $search ; echo $post;`
searchdevice=`./searchdevice.sh $device $traf`
pre=`echo $searchdevice | awk 'NR==1{printf"%s",$1}'`
post=`echo $searchdevice | awk 'NR==3{printf"%s",$1}'`
search=`echo $afteradd`
end=`echo -n $pre ; echo -n $search ; echo $post;`
#echo to file
echo $end  
else
search=`echo $search | sed "s/]}/$oper]}/"`
afteradd=`echo -n $pre ; echo -n $search ; echo $post;`
searchdevice=`./searchdevice.sh $device $traf`
pre=`echo $searchdevice | awk 'NR==1{printf"%s",$1}'`
post=`echo $searchdevice | awk 'NR==3{printf"%s",$1}'`
search=`echo $afteradd`
end=`echo -n $pre ; echo -n $search ; echo $post;`
#echo to file
echo $end 
fi
