#!/usr/local/bin/zsh
cd /TopStor
rm -rf key/adminfixed.gpg && cp factory/adminfixed.gpg key/adminfixed.gpg
/TopStor/autoGenPatch
