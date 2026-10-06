#!/usr/bin/sh
# Intentionally empty.  systempull.sh / csystempull.sh no longer run this file: the hooks are per branch,
# apply.d/<branch>/pre_apply.sh and apply.d/<branch>/post_apply.sh (stubs made by mkapplyhooks.sh).
# The React-UI build that used to live here (quickstor-ui:latest, /topstorweb/build_react) was removed on purpose.
exit 0
