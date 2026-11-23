#!/bin/sh
glog='/TopStordata/TopStorglobal.log'
catalog='/TopStor/msgsglobal.txt'
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

if [ $# -eq 6 ]; then
    # A message without arguments is written as "<code>@@" (the format before the @@@ check; getlogs.py reads it).
    # It is accepted only for a catalog code that has no ':' placeholder, so a call that forgot its arguments
    # (or an unknown code, which info/logs cannot show) is still refused.
    if [ -r "$catalog" ]; then
        nph=`awk -v c="$msg" 'index($0, c":") == 1 { n = 0; for (i = 5; i <= NF; i++) if ($i == ":") n++; print n; exit }' "$catalog"`
        if [ -z "$nph" ]; then
            error_detail="unknown message code $msg without arguments"
        elif [ "$nph" -gt 0 ]; then
            error_detail="incorrect format: $msg needs $nph arguments, received none"
        fi
    fi
elif ! echo "$code" | grep -q "@@@"; then
    error_detail="incorrect format: missing @@@ separator in $msg"
fi

if [ -n "$error_detail" ]; then
    echo "$dt $tm $fromhost error system admin LogError@@@error while logging message: $error_detail $dtn" >> $glog
    exit 1
fi

# test 677: a row can reach this file twice (live from the sender, and again when a node that was down catches up from the
# log/<id> copy in etcd, pace/checksyncs.py synclogcopy; or from a second receiver): the same date, time, host, type, user and
# code are written once
grep -qF -- "$dt $tm $fromhost $msgtype $msguser $code " $glog 2>/dev/null && exit 0
echo $dt $tm $fromhost $msgtype $msguser $code $dtn >> $glog
