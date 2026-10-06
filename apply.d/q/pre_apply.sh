#!/bin/sh
# pre_apply hook of branch q -- run by systempull.sh / csystempull.sh first, after the cluster sync of the pull,
# only when this branch was pulled.  Argument 1 = the branch.  Empty on purpose: put here whatever
# this branch needs on a node after a pull (rebuild, migrate, restart ...).  A non-zero exit is reported
# and makes the pull finish "with errors", it does not stop it.
exit 0
