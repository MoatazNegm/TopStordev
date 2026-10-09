#!/bin/sh
# post_apply hook of branch QSD5.266 -- run by systempull.sh / csystempull.sh last, after pre_apply,
# only when this branch was pulled.  Argument 1 = the branch.  Empty on purpose: put here whatever
# this branch needs on a node after a pull (rebuild, migrate, restart ...).  A non-zero exit is reported
# and makes the pull finish "with errors", it does not stop it.
exit 0
