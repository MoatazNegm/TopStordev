#! /usr/local/bin/zsh
oper1=` echo $@ | awk '{print $1}'`;
oper2=` echo $@ | awk '{print $2}'`;
stat=`./iostat.sh $oper1`
statdate=` echo $stat | awk -F\| '{ print $2 }'`;
i=`echo $stat | awk -F\| '{ print "time "$3" bw "$4" rs "$5" ws "$6" svct "$7" qlen "$8}' | awk '{$1=$1}{ print }'`; xi=` ./jsonthis3.sh $i`; ./addtime.sh $oper1 $statdate $xi $oper2 
