#! /bin/sh
cd /TopStor
instr=`echo $@ | awk '{print $1}'`;
for snapshot in `zfs list -H -t snapshot | grep -w "$instr" | cut -f 1`
do
zfs destroy $snapshot
done
echo ready;
