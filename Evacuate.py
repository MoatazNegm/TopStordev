#!/bin/python3.6
import subprocess,sys, datetime
import json
from etcdput import etcdput as put 
import logmsg
def do(*args):
 logmsg.sendlog('Evacuaest01','info',args[-1],args[-2])
 put('toremove/'+args[-2],'start')
 put("tosync","yes")

if __name__=='__main__':
 do(*sys.argv[1:])
