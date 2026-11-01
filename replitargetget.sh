#!/bin/sh
echo $@ > /root/replitargetget
cd /TopStor
partner=`echo $@ | awk '{print $1}'`
volume=`echo $@ | awk '{print $2}'`
volsize=`echo $@ | awk '{print $3}'`
snapshot=`echo $@ | awk '{print $4}'`
partnerinfo=`./etcdgetlocal.py Partner/$partner`
replitype=`echo $partnerinfo | awk -F'/' '{print $2}'`
pport=`echo $partnerinfo | awk -F'/' '{print $3}'`
clusterip=`./etcdgetlocal.py namespace/mgmtip | awk -F'/' '{print $1}'`
phrase=`echo $partnerinfo | awk -F'/' '{print $NF}'`
# QSD5.344: the stored phrase is encrypted ('enc~...'); a clear phrase of an older version comes back unchanged
phrase=`/TopStor/secretmask.py phrasedec "$partner" "$phrase"`
isopen='closed'
echo pport=$pport
strict='-oStrictHostKeyChecking=yes' 
partnersinfo=`./etcdgetlocal.py Partnernode/$partner --prefix`
echo partnersinfo=$partnersinfo
echo "$partnersinfo" | while read node 
do
 echo node=$node
 echo $node | grep '.' 
 if [ $? -ne 0 ];
 then
  partnerip=`echo $partnerinfo | awk -F'/' '{print $1}'`
  isnew='new'
 else 
  partnerip=`echo $node | awk -F'/' '{print $3}'`
  isnew='old'
 fi
 echo isopen=$isopen
 echo $isopen | grep open
 if [ $? -eq 0 ];
 then
  break
 fi
 echo partnerip=$partnerip
 echo ./checkpartner.sh $partner $replitype $partnerip $pport $clusterip "****" $isnew
 isopen=`./checkpartner.sh $partner $replitype $partnerip $pport $clusterip $phrase $isnew`
 echo isnew=$isopen 
 echo $isopen | grep open
 if [ $? -ne 0 ];
 then
  continue
 fi
 echo $partnerip $pport
 nodeloc='ssh -oBatchmode=yes -i /TopStordata/'${partnerip}'_keys/'${partnerip}' -p '$pport' -oStrictHostKeyChecking=yes  '${partnerip}
 echo nodeloc /TopStor/repliSelection.py $volume $volsize $snapshot
 xx=`$nodeloc /TopStor/repliSelection.py $volume $volsize $snapshot`
 echo $xx | grep 'result'_
done


