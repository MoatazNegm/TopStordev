#!/bin/sh
username=`echo $@ | awk '{print $1}'`
userpass=`echo $@ | awk '{print $2}'`
# '-': the secret is read from stdin, so it is not on a command line (ps, traces); the iSCSI CHAP secret (fapi)
[ "$userpass" = "-" ] && read -r userpass
encthis=`echo "$userpass" | openssl enc -d -e  -base64 -aes-256-ctr  -pbkdf2 -nopad -k '#skMe22'$username`
echo _result${encthis}_result
