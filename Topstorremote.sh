#!/usr/local/bin/zsh
cd /TopStor
partners='/TopStordata/partners.txt'
#rm /tmp/msgremotefile 2>/dev/null
#rm /tmp/msgrack 2>/dev/null
#mkfifo -m 600 /tmp/msgremotefile 2>/dev/null
#mkfifo -m 600 /tmp/msgrack 2>/dev/null
echo $$ > /var/run/topstorremote.pid
ClearExit() {
	echo got a signal > /TopStor/txt/sigstatusremote.txt
	rm /tmp/msgremotefile;
        rm /tmp/msgrack;
	rm /var/run/topstorremote.pid
	exit 0;
}
trap ClearExit HUP
#./ProxySVC.sh &
while true; do
{
egrep -E "Dual|receiv|send" $partners 
if [ $? -eq 0 ]; then
 echo hi
 hosts=(`egrep -E "Dual|receiv|send" $partners | awk '{print $1}'`)
 for host in "${hosts[@]}"; do
  sshost=`echo $host | awk '{print $1}'`
   echo sshost=$sshost
  ping -w 1 $sshost &>/dev/null
  if [ $? -eq 0 ]; then
   hostnam=`ssh root@$sshost cat /TopStordata/hostname`
   scp $sshost:/pacedata/iscsitargets /TopStordata/partner_${sshost}_targets
   partnsers=(`cat /TopStordata/partner_${sshost}_targets | awk '{print $2}'`);
   echo ${partners[@]} | while read -r verhost; do
     /TopStor/Partnerprep $verhost &>/dev/null
   done
   echo hostnam=$hostnam
   cat $partners | grep "$hostnam"
   if [ $? -ne 0 ]; then
    hostline=`cat $partners | grep "$sshost"`
    hostupd=${hostline}' '$hostnam' '$partnerhost
    echo $hostupd
    hostless=(` cat $partners | grep -v $sshost`)
    echo "${hostless[@]}" > $partners
    echo $hostupd >> $partners
   fi
  fi
 done
fi
sleep 20
}
done;
echo it is dead >/TopStor/txt/statusremote.txt
