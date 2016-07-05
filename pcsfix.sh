#!/usr/local/bin/zsh
cd /TopStor
echo $$ > /var/run/pcsfix.pid
#rm /TopStor/txt/*
ClearExit() {
	exit 0;
}
trap ClearExit HUP
sleep 10
while true; do 
{
pcsitems=`pcs resource`;
echo $pcsitems | grep ocf | grep -v Started  &>/dev/null
if [ $? -eq 0 ]; then
 fsvcs=(`echo $pcsitems | grep ocf | grep -v Started | awk '{print $1}'`)
 for svc in "${fsvcs[@]}"; do
  pcs resource debug-start $svc
  pcs resource cleanup $svc
 done
 ps -ef | grep Topstor | grep zsh &>/dev/null
 if [ $? -ne 0 ]; then
  systemctl stop topstor 
  systemctl start topstor 
 fi
 
fi  
sleep 5
}
done;
