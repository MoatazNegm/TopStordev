#!/usr/local/bin/zsh
export PRE; export POST; export SEARCHY;

function searchdevice() {
 device=$1
 logs=$2
 logcont=`cat $logs`;
 echo $logcont | grep -w $device  > /dev/null 2>&1
 if [[ $? -ne 1 ]];
 then
  separat='{"name":"'${device};
  pre=${logcont%${separat}*};
  cpre=${#pre};
  csep=${#separat}; 
  searchpost=${separat}${logcont:$((csep+cpre))}
  separat2='}]}]}]}'
  search=${searchpost%%${separat2}*}${separat2};
  post=${searchpost:${#search}}
  if [[ -z $post ]]; then post=']}'; fi
 else
  search=""
  post=`echo "]}"`
  if [[ -z $logcont ]]; then pre='{"device":[';
  else pre=${logcont:0:-2}',';
  fi
 fi
 echo PRE=${pre} > txt/searchdev
 echo POST=${post} >> txt/searchdev
 echo SEARCHY=${search} >> txt/searchdev
}

function searchdate() {
 date=$1
 traf=$2
 search1=`cat txt/searchdate`; 
 echo $search1 | grep -w $date > /dev/null 2>&1
 if [[ $? -ne 1 ]];
 then
  search=${search1:0:-4};
  pre=""
  post="]}]}"
 else
  pre=${search1:0:-4};
  search=""
  post="]}]}"
 fi
 echo PRE=${pre} > txt/searchdate
 echo POST=${post} >> txt/searchdate
 echo SEARCHY=${search} >> txt/searchdate
}

device=` echo $@ | awk '{print $1}'`;
traf=` echo $@ | awk '{print $2}'`;
stat=`./iostat.sh $device`
statdate=` echo $stat | awk -F\| '{ print $2 }' | awk '{print $1}'`;
date=`echo $statdate | awk -F\/ '{print $2"/"$1"/"$3}'`;
i=`echo $stat | awk -F\| '{ print "time "$3" bw "$4" rs "$5" ws "$6" svct "$7" qlen "$8}' | awk '{$1=$1}{ print }'`;
oper=` ./jsonthis3.sh $i`;
searchdevice $device $traf;
#search=$SEARCHY; devpre=$PRE; devpost=$POST
# first time for this device 
search=`cat txt/searchdev | grep SEARCHY`
devpre=`cat txt/searchdev | grep PRE`
devpost=`cat txt/searchdev | grep POST`
devpost=${devpost:5}
devpre=${devpre:4}
search=${search:8}
if [[ -z $search ]];
then 
 search='{"name":"'$device'","stats":[{"Dates":[{"Date":"'$date'","times":['$oper']}]}]}';
else
 echo $devpre | grep -w device > /dev/null 2>&1 
 if [[ $? -ne 0 ]]; then devpre='{"device":['$devpre; fi;
 echo $search > txt/searchdate
 searchdate $date $traf ;
search=`cat txt/searchdate | grep SEARCHY`
pre=`cat txt/searchdate | grep PRE`
post=`cat txt/searchdate | grep POST`
post=${post:5}
pre=${pre:4}
search=${search:8}
 devpre=${devpre}$pre; devpost=${post}${devpost}
# first time for this date in this device
 if [[ -z $search ]];
 then
  search=',{"Date":"'$date'","times":['$oper']}';
 else 
  search=${search:0:-2}','$oper']}';
 fi
fi  
end=${devpre}${search}${devpost}
echo $end > ${traf}
