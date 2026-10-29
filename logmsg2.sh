#!/bin/sh
glog='/TopStordata/TopStorglobal.log'
dtn=`date +%s`

raw_args="$@"
dt=`echo $raw_args | awk '{print $1}'`
tm=`echo $raw_args | awk '{print $2}'`
fromhost=`echo $raw_args | awk '{print $3}'`
msg=`echo $raw_args | awk '{print $4}'`
msgtype=`echo $raw_args | awk '{print $5}'`
msguser=`echo $raw_args | awk '{print $6}'`

error_detail=""

if [ $# -lt 6 ]; then
    error_detail="incorrect format: insufficient arguments (received $#)"
elif [ -z "$msg" ]; then
    error_detail="no message code provided"
elif echo "$msg" | grep -q " "; then
    error_detail="incorrect format: message code contains spaces"
fi

if [ -n "$error_detail" ]; then
    echo "$dt $tm $fromhost error system admin LogError@@@error while logging message: $error_detail $dtn" >> $glog
    exit 1
fi

logcode=$msg'@'$dt'@'$tm'@'$fromhost
x=7; code=$msg'@@'
while [ $x -le $# ]; do
    val=`echo $raw_args | awk -v xx=$x '{print $xx}'`
    logcode=$logcode'@'$val
    code=$code'@'$val
    x=$((x+1))
done

# QSD5.337: a message with no argument ($# = 6: date time host code type user) has only the "@@" after the code and is valid
if [ $# -gt 6 ] && ! echo "$code" | grep -q "@@@"; then
    error_detail="incorrect format: missing @@@ separator in $msg"
    echo "$dt $tm $fromhost error system admin LogError@@@error while logging message: $error_detail $dtn" >> $glog
    exit 1
fi

echo $dt $tm $fromhost $msgtype $msguser $code $dtn >> $glog
