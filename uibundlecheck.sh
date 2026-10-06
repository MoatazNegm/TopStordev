#!/bin/sh
# uibundlecheck.sh -- does the built React UI carry the new-user rules of src/utils/userRules.js?
# prints e.g. "name:1 pass:1 dup:1" (1 = the message is in the bundle)
d=/topstorweb/build_react/assets
f() { grep -l "$1" $d/*.js 2>/dev/null | head -1 | grep -c . ; }
echo "name:`f 'starting with a letter'` pass:`f 'The password must not contain blanks'` dup:`f 'A user with this name already exists'`"
