#! /bin/sh
instr=`echo $@ | awk '{print $1}'`;
oper=`echo $@ | awk '{$1=""; print $0 }'`;
$instr $oper
