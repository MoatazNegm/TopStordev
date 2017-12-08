#!/usr/local/bin/zsh
#
#   Remove CRLF, trailing whitespace and double lining.
#   $MERHABA: ascii_clean.sh,v 1.0 2007/11/11 15:09:05 kyrre Exp $
#

for file in `find -s . -type f`; do

         if file -b $file | grep -q 'text'; then

                 echo >> $file

 tr -d '\r' < $file | cat -s | sed -E -e 's/[[:space:]]+$//' > $file.tmp

                mv -f $file.tmp $file

                 echo "$file: Done"

         fi

done
chmod 700 * ;
chmod 600 *.txt;
chmod 600 *.log;

