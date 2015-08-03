#! /usr/local/bin/zsh
cd /TopStor
ClearExit() {
	echo got a signal > /TopStor/txt/sigstatusremote.txt
	kill -9 `ps -ef | grep nc  | awk '{print $1}'`
	exit 0;
}
trap ClearExit HUP
/sbin/sysctl net.inet.tcp.msl=2500 >/dev/null
while true; do
{
nc -ld 2234 | gunzip | openssl enc -d -aes-256-cbc -a -A -k SuperSecretPWD > /tmp/msgremotefile & 
read line < /tmp/msgremotefile;
echo $line > /TopStor/tmplineremote;
 remoteinit=` echo $line | grep Proxy | wc -c `;
if [[ $remoteinit -ge 3 ]]; then
 ./remoteReceived;
fi
}
done;
echo it is dead >/TopStor/txt/statusremote.txt
