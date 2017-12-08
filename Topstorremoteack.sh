#!/usr/local/bin/zsh
cd /TopStor
rm /tmp/msgrack 2>/dev/null
mkfifo -m 600 /tmp/msgrack 2>/dev/null
echo $$ > /var/run/topstorremoteack.pid
ClearExit() {
        echo got a signal > /TopStor/txt/sigstatusremoteack.txt
        rm /tmp/msgrack;
        rm /var/run/topstorremoteack.pid
         exit 0;
}
trap ClearExit HUP
#./ProxySVC.sh &
while true; do
{
#nc -l 2235 --ssl-cert /TopStor/key/TopStor.crt --ssl-key /TopStor/key/TopStor.key  > /tmp/msgrack
hosts=(`cat /TopStordata/partners.txt /pacedata/iscsitargets | egrep -E "Dual|receiver" | awk '{print $1}' | sort -u`)
for host in "${hosts[@]}"; do
 sshost=`echo $host | awk '{print $1}'`
 ps -ef | grep "$sshost" | grep  root\@ | grep master  &>/dev/null
 if [ $? -ne 0 ]; then
  ssh -t -t -o ControlPath=~/.ssh/master-$sshost -o ControlMaster=auto -o ControlPersist=600000000000000 root@$sshost ""   & 
 fi
done
 sleep 5
}
done;
