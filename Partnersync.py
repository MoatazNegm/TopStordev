#!/usr/bin/python3
import sys
from etcdgetlocalpy import etcdget as get 
from PartnerAdd import addpartner as addpartner
from secretmask import phrase_decrypt


def partnersync(*bargs):
 partneralias = bargs[0]
 partnerinfo = get('Partner/'+partneralias)[0].split('/')
 partnerip = partnerinfo[0]
 replitype = partnerinfo[1]
 repliport = partnerinfo[2]
 # QSD5.344: the stored phrase is encrypted ('enc~...'); addpartner encrypts it again, so it gets the clear one
 phrase = phrase_decrypt(partneralias, partnerinfo[3])
 userreq = 'system'
 init = 'local'
 addpartner(partnerip, partneralias, replitype, repliport, phrase, userreq, init )
 

if __name__=='__main__':
 partnersync(*sys.argv[1:])
