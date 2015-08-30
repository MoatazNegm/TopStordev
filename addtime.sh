#!/usr/local/bin/zsh
export PRE; export POST; export SEARCHY;

function searchdevice() {
 device=$1
 logs=$2
 devices=`cat $logs | /usr/local/bin/jq '.[]|.[] | .name'| sed 's:"::' | sed 's:"::'`
 json=`cat $logs | /usr/local/bin/jq  -c '.[]'`
 json1=`echo $json | /usr/local/bin/jq -c '.[]'`
 json2=`echo "{\"device\":[\n"$json1"\n]}"`
 echo $devices | grep -w $device  > /dev/null 2>&1
 if [ $? -ne 1 ]
 then
  search=`echo $json2 | grep -w $device`
  pre=`echo $json2 | grep -w -B99999999 $device| grep -v -w $device | tr "\n" "," | sed 's:\[,:\[:'`
  post=`echo $json2 | grep -w -A99999999 $device| grep -v -w $device| tr "\n" ","|sed 's:^:,:'|sed 's:,]},$:]}:'`
 else
  json2=`echo "{\"device\":[\n"$json1"\n"`
  pre=`echo $json2 |tr "\n" "," | sed 's:\[,:\[:'`
  search=""
  post=`echo "]}"`
 fi
 chksearch=` echo $search | wc -c `
 if [[ $chksearch -le 40 ]]; then search=""; fi
 PRE=$pre; POST=$post; SEARCHY=$search
}

function searchdate() {
 date=$1
 traf=$2
 search1=` echo $@ | awk '{$1=$2=""; print substr($0,3)}'`; 
 dates=`echo $search1 | /usr/local/bin/jq -c '.[]'| awk 'NR==2{printf"%s",$1}'| /usr/local/bin/jq -c '.[]|.[]|.[]|.Date'| sed 's:"::' | sed 's:"::'`
 json=`echo $search1 | /usr/local/bin/jq -c '.[]'| awk 'NR==2{printf"%s",$1}'| /usr/local/bin/jq -c '.[]|.[]|.[]'`
 echo $dates | grep -w $date > /dev/null 2>&1
 if [ $? -ne 1 ]
 then
  json1=`echo "{\"name\":\"$device\",\"stats\":[{\"Dates\":[\n"$json"\n]}]}"`
  echo $json1 |grep -w $date | grep -w "times" > /dev/null 2>&1
  if [ $? -ne 1 ]
  then
   search=`echo $json1 | grep -w $date`
  else
   search=""
  fi
  pre=`echo $json1 | grep -w -B99999999 $date| grep -v -w $date | tr "\n" "," | sed 's:\[,:\[:'`
  post=`echo $json1 | grep -w -A99999999 $date| grep -v -w $date| tr "\n" ","|sed 's:^:,:'|sed 's:,]}]},$:]}]}:'`
 else
  json=`echo $json`
  pre=`echo "{\"name\":\"$device\",\"stats\":[{\"Dates\":[\n"$json"\n"|tr "\n" ","| sed 's:\[,:\[:' | sed 's:\]},,:]},:'| sed 's:\[,,:[:' `
  search=`echo "{\"Date\":\"$date\",\"times\":[]}"`
  post=`echo "]}]}"`
 fi
 chksearch=` echo $search | wc -c `
 if [[ $chksearch -le 40 ]]; then search=""; fi
 PRE=$pre; POST=$post; SEARCHY=$search
}

device=` echo $@ | awk '{print $1}'`;
date=` echo $@ | awk '{print $2}'`;
traf=` echo $@ | awk '{print $3}'`;
oper=` echo $@ | awk '{$1=$2=$3="";print substr($0,4)}'`;
searchdevice $device $traf;
search=$SEARCHY; pre=$PRE; post=$POST
# first time for this device 
if [[ -z $search ]];
then 
 search='{"name":"'$device'","stats":[{"Dates":[{"Date":"'$date'","times":['$oper']}]}]}';
 devpre=$pre; devpost=$post; devsearch=$search
else
 devpre=$pre; devpost=$post; devsearch=$search
 echo $pre | grep -w device > /dev/null 2>&1 
 if [[ $? -ne 0 ]]; then devpre='{"device":['$pre; else devpre=$pre; fi;
 searchdate $date $traf $search;
 devpre=${devpre}$PRE; devpost=${POST}${devpost}
 search=$SEARCHY; 
# first time for this date in this device
 if [[ -z $search ]];
 then
  search='{"Date":"'$date'","times":['$oper']}';
 else 
  search=${search:0:-2}','$oper']}';
 fi
fi  
end=${devpre}${search}${devpost}
echo $end > ${traf}
