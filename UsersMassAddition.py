#!/usr/bin/python3
import subprocess, pandas as pd, sys, os
from logmsg import sendlog, initlog
# Replacement for etcdgetjson
def cleaner(result):
    mylist=str(result.stdout.decode()).replace('\n\n','\n').split('\n')
    mylist=zip(mylist[0::2],mylist[1::2])
    hostid=0
    hosts=[]
    for x in mylist:
        ll=[]
        xx=x[1]
        ll.append(xx)
        hostsdic={'id':str(hostid),'name':x[0],'prop':xx}
        hostid=hostid+1
        hosts.append(hostsdic)
    return hosts

# Replacement for etcdget
def poolsCleaner(result):
    z=[]
    mylist=str(result.stdout.decode()).replace('\n\n','\n').split('\n')
    zipped=zip(mylist[0::2],mylist[1::2])
    for x in zipped:
        z.append(x) 
    return z

def getusers():
    cmdline = ['docker', 'exec', 'etcdclient', 'etcdctl', '--endpoints=http://etcd:2379', 'get', 'usersinfo', '--prefix']
    userlst = cleaner(subprocess.run(cmdline,stdout=subprocess.PIPE))
    uid = 0
    users = []
    for user in userlst:
        username = user['name'].replace('usersinfo/','')
        users.append([username,str(uid)]) 
        uid += 1
    return users

def getgroups():
    cmdline = ['docker', 'exec', 'etcdclient', 'etcdctl', '--endpoints=http://etcd:2379', 'get', 'usersigroup', '--prefix']
    groupslst = cleaner(subprocess.run(cmdline,stdout=subprocess.PIPE))
    gid = 0
    groups = []
    for group in groupslst:
        grpusers = group['prop'].split('/')[2]
        groupname = group['name'].replace('usersigroup/','')
        groups.append([groupname,str(gid), grpusers]) 
        gid += 1
    return groups

def getpools():
    cmdline=['docker', 'exec', 'etcdclient', 'etcdctl', '--endpoints=http://etcd:2379', 'get', 'pools/', '--prefix']
    pools= poolsCleaner(subprocess.run(cmdline,stdout=subprocess.PIPE))
    poolinfo = []
    pooldict = dict()
    pid = 0
    for pool in pools:
        poolinfo.append({'id':pid, 'owner': pool[1], 'text':pool[0].split('/')[1]})
        pid += 1
        pooldict[pool[0].split('/')[1]] = {'id': pid, 'owner': pool[1] }
    return poolinfo

def poolsinfo():
    allpools = getpools()
    allpools.append({'id':len(allpools), 'text':'-------'})
    return {'results':allpools}

def api_users_userslist():
    global allgroups, allusers, leaderip
    cmdline = ['docker', 'exec', 'etcdclient', 'etcdctl', '--endpoints=http://etcd:2379', 'get', 'usersinfo', '--prefix']
    userlst = cleaner(subprocess.run(cmdline,stdout=subprocess.PIPE))
    allgroups = getgroups()
    userdict = dict()
    allusers = []
    for group in allgroups:
        groupid = group[1]
        grpusers = group[2].split(',')
        for grpuser in grpusers:
            if grpuser not in userdict:
                userdict[grpuser] = []
            userdict[grpuser].append(str(groupid))
    usersnohome = []
    nohomeid = 0
    uid = 0
    for user in userlst:
        username = user['name'].replace('usersinfo/','')
        usersize = user['prop'].split('/')[3]
        userpool = user['prop'].split('/')[1]
        priv = '/'.join(user['prop'].split('/')[4:])
        if username not in userdict:
            groups = ['NoGroup']
        else:
            groups = userdict[username]
        allusers.append({"name":username, 'id':uid, "pool":userpool, "size":usersize, "groups":groups, 'priv':priv})
        uid += 1
        if 'NoHome' in userpool:
            usersnohome.append({ 'id':nohomeid, 'text': username })
            nohomeid += 1 
    alldict = dict()
    alldict['allusers'] = allusers
    alldict['allgroups'] = allgroups
    alldict['usersnohome'] = usersnohome
    return alldict

def api_groups_userlist():
    global allgroups
    allgroups = getgroups()
    grp = []
    for group in allgroups:
        grp.append({'id':group[1],'text':group[0]})
    return {'results':grp}

# Checks if the User is valid or not.
def checker(user, usersNames, poolNames, groupNames, newGroups):
    flag = False
    if (user['name'] in usersNames or  pd.isnull(user['name']) or user['name'] == ''):
        flag = True
    if ( pd.isnull(user['Password']) or len(user['Password']) < 3):
        flag = True
    # Checks if the user selected a Pool.
    if (not (pd.isnull(user['Volpool']) or user['Volpool'] == '')):
        if (user['Volpool'] != len(user['Volpool']) * '-'):
            # Checks that the Pool is valid.
            if (not (user['Volpool'].lower() in poolNames)):
                flag = True

    # Checks if the user selected a group.
    if (not (pd.isnull(user['groups']) or user['groups'] == '')):
        # Checks that each group selected is valid.
        for group in user['groups'].split(','):
            if (group): 
                if (not (group.strip() in groupNames) and len(group.strip()) < 3):
                    flag = True
                elif (not (group.strip() in groupNames) and group.strip() != "NoGroup"):
                    newGroups.add(group.strip())
        
    # Checks if the user selected a HomeAddress.
    if (not(pd.isnull(user['HomeAddress']) or user['HomeAddress'] == '' or user['HomeAddress'].lower()  == 'NoAddress'.lower() or user['HomeAddress'].lower()  == 'No Address'.lower())):
        # Checks if the HomeAddress is in the correct form.
        if (len(user['HomeAddress'].split('.')) == 4):
            # Checks that each number is valid.
            for number in user['HomeAddress'].split('.'):
                if (not number.isdigit()):
                    flag = True
                elif (int(number) > 255 or int(number) < 0):
                    flag = True
        else:
            flag = True
    return flag

# Takes in the Excel file path, it parses the file and creates goodusers list
def excelParser(filePath):
    df = pd.read_excel(filePath, dtype = str)
    df = df.loc[:, ~df.columns.str.contains('^Unnamed')]
    df = df.fillna('')
    df['name'] = df['name'].str.rstrip()
    df['Volpool'] = df['Volpool'].str.rstrip()
    df['HomeAddress'] = df['HomeAddress'].str.rstrip()
    df['HomeSubnet'] = df['HomeSubnet'].str.rstrip()
    df['Volsize'] = df['Volsize'].str.rstrip()
    users = api_users_userslist()['allusers']
    groups = api_groups_userlist()['results']
    pools = poolsinfo()['results']
    usersNames = [user['name'] for user in users]
    groupNames = [group['text'] for group in groups]
    poolNames = [pool['text'].lower() for pool in pools]
    poolNames.append('nohome')
    poolNames.append('no home')
    poolNames.append('nopool')
    poolNames.append('no pool')
    
    goodUsers = []
    badUsers = []
    newGroups = set()
    for index, user in df.iterrows():
        flag = checker(user, usersNames, poolNames, groupNames, newGroups)
        if flag:
            badUsers.append(user)
        else:
            goodUsers.append(user)
            usersNames.append(user['name']);
    return goodUsers, newGroups

# Takes in leaderip, user and Excel file. Creates a list of goodusers and addes them using UnixAddUser script.
def addUsers(*argv):
    users, newGroups = excelParser(argv[3])
    pools = poolsinfo()['results']
    groups = api_groups_userlist()['results']
    poolNames = [pool['text'].lower() for pool in pools]
    groupNames = [group['text'] for group in groups]
    
    for newGroup in newGroups:
        cmdline = '/TopStor/UnixAddGroup {} {} usersNoUser {}'.format(argv[0], newGroup, argv[1])
        subprocess.run(cmdline.split(' '))
    
    for user in users:
        pool = 'NoHome'
        groups = []
        address = 'NoAddress'
        subnet = '8'
        size = '1'
        if (user['Volpool'] in poolNames and len(user['Volpool']) * '-' != user['Volpool'] ):
            pool = user['Volpool']
        if (not (user['groups'] == '')):
            for g in user['groups'].split(','):
                if (g in groupNames or len(g) > 3):
                    groups.append(g)
            groups = ','.join(groups)
        else:
            groups = ''
        if (not (user['HomeAddress'] == '')):
            if (user['HomeAddress'].lower() != 'No Address'.lower()):
                address = user['HomeAddress']
        if (not (user['HomeSubnet'] == '')):
            subnet = user['HomeSubnet']
        if (not (user['Volsize'] == '')):
            size = user['Volsize']
        cmdline = '/TopStor/UnixAddUser {} {} {} groups{} {} {}G {} {} hoststub {}'.format(argv[0], user['name'], pool, groups, user['Password'],size, address, subnet, argv[1])
        subprocess.run(cmdline.split(' '))
    initlog(argv[0], argv[2])
    sendlog('Unlin1027', 'info', argv[1])
    os.remove(argv[3])   


if __name__=='__main__':
 with open('/root/fileupload','w') as f:
    f.write(' '.join(sys.argv[1:]))
 addUsers(*sys.argv[1:])
