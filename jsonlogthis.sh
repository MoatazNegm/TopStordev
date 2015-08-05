#!/usr/local/bin/zsh
# needed the operands to be like : Date time info/warning/error _message info_
str=$@;
oper4=`echo $@ | awk -F_ '{print $2}'`;
oper=($(echo ${str}));
n=`echo ${#oper[@]}`
workingdate=`echo txt/currentlog.log | grep "$oper[1]"`;
if [[ -z $workingdate ]]; then
 js=`echo \{\"Date\":\"${oper[1]}\",\"times\":\[\{\"time\":\"${oper[2]}\",\"msg\":\"${oper[3]}\",\"data\":\"${oper4}\"\}\]\}`
 echo $js
fi
currentlog=`cat txt/currentlog.log | rev | cut -c 3- | rev`
echo $currentlog
echo ${currentlog}\,${js}\]\} > txt/currentlog.log

