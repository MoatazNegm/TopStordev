#!/usr/bin/sh
fnloop () {
cd /TopStor
# test 679: one receiver per node: an orphaned receiver (its looper killed) keeps serving, no second one is started next to it
if ps -eo args | grep -q '^/usr/bin/python3 /TopStor/topstorrecvreply.py'; then
 sleep 2
 return
fi
/TopStor/topstorrecvreply.py
}
while true;
do
 fnloop 
 sleep 1 
done
