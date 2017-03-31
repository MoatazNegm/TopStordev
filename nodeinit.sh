#!/bin/sh
wifi=`ip a | grep ": wlp"  | tail -1 |awk -F": " '{print $2}'`
ether=`ip a | grep "2: "  | head -1 |awk -F": " '{print $2}'`
ip address add 10.1.1.10/24 dev $ether:0
wpa_passphrase "VodafoneMobileWiFi-2F1A09" 9276916326 > /etc/wpa.wifi
sed -e "s/ETHER/$ether/g" -e "s/WLP/$wifi/g" -e "s/\#dh/dh/g" wpa.conf > wpa
chmod 700 wpa
