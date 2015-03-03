#!/usr/local/bin/zsh
cd /TopStor
while true; do
{
nc -l 2235 | gunzip | openssl enc -d -aes-256-cbc -a -A -k SuperSecretPWD ;
}
done;
