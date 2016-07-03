#!/usr/local/bin/zsh
cd /TopStor
logging='/var/www/html/des20/Data/currentinfo2.log'
vol=`echo $@ | awk '{print $1}'`;
volsize=`echo $@ | awk '{print $2}'`;
volsize=$((volsize+1))
pools=(`cat /pacedata/pools/runningpools  | grep -v runningpools| awk '{print $1" "$2" "$5}' | sed '    s/\([0-9][0-9]*\(\.[0-9]\+\)\?\)K/\1000/g;
      s/\([0-9][0-9]*\(\.[0-9]\+\)\?\)\./\1/g;
      s/\([0-9][0-9]*\(\.[0-9]\+\)\?\)M/\1000000/g;
      s/\([0-9][0-9]*\(\.[0-9]\+\)\?\)G/\1000000000/g;
      s/\([0-9][0-9]*\(\.[0-9]\+\)\?\)T/\1000000000000/g;
      s/\([0-9][0-9]*\(\.[0-9]\+\)\?\)P/\1000000000000000/g;
      s/\([0-9][0-9]*\(\.[0-9]\+\)\?\)E/\1000000000000000000/g
' `)
echo ${pools[@]} | while read -r pool; do
 poolfree=`echo $pool | awk '{print $3}' `
 poolfree=$((poolfree+1));
 if [ $poolfree -gt $volsize ]; then
   sshost=`echo $pool | awk '{print $1}' `
   targetpool=`echo $pool | awk '{print $2}' `
   targetip=` cat /etc/hosts | grep "$sshost" | awk '{print $1}'`
   echo $targetip  $targetpool 
   exit 0;
 fi
done
echo nothing
