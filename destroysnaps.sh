#!/usr/local/bin/zsh
cd /TopStor
res=`echo $@ | awk '{print $1}'`;
instr=`echo $@ | awk '{print $2}'`;
for snapshot in `zfs list -H -t snapshot | grep -w "$instr" | cut -f 1`
do
zfs destroy $snapshot
done
echo ready > $res
