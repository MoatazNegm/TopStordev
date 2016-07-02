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
nc -l 2235 --ssl-cert /TopStor/key/TopStor.crt --ssl-key /TopStor/key/TopStor.key  > /tmp/msgrack
}
done;
