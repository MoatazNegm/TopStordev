#!/bin/sh
# usage: cifsacl.sh <dir> <groups>      (groups comma separated, as the share record keeps them; 'nogroup' = no group)
#
# QSD5.352 r10c (QC proof 10, C-1/C-2): the rights of a CIFS share, set by VolumeCreateCIFS and VolumeChangeCIFS
# (one place, so a share change cannot undo what the create set: C-1, VolumeChangeCIFS ran an old tail after the r10
# block that wiped the default ACLs again with setfacl -b -R).
#
# Semantics (decided in r10c, DEVELOPMENT.md section 130 "Round 10c"):
#   - the share root is 3770 (setgid + sticky): a share group member creates files and folders in it, and nobody but
#     the owner (and root/administrator) deletes or renames them;
#   - every member READS every file and folder of the share (QC 642); a member CHANGES only what he owns: the group
#     entry of files and sub-folders is r-x (X: only folders / executables get x), not rwx.  Samba 4.8 (quickstor:smb)
#     copies the parent's default ACL to a new file and sets the mask to rwx whatever the share's create mask is, so a
#     default group entry rwx let a member overwrite another member's file (C-2, QC proof 531.1/531.2);
#   - a sub-folder is like a file: its owner writes in it, the other members read it;
#   - users outside the share groups get nothing (o::--- also as default).
[ -n "$1" ] || exit 1
d=$1
groups=`echo "$2" | sed 's/,/ /g'`
[ -d "$d" ] || { echo "cifsacl.sh: $d is not a directory"; exit 1; }
chmod 3770 "$d"
setfacl -b -R "$d"
echo " $groups " | grep -qw nogroup && groups=''
for grp in $groups
do
	setfacl -R -m g:$grp:r-X "$d"                                        # existing content: members read
	setfacl -m g:$grp:rwx "$d"                                           # share root: members create
	setfacl -d -m g:$grp:r-x "$d"                                        # new content: members read
	find "$d" -mindepth 1 -type d -exec setfacl -d -m g:$grp:r-x {} + 2>/dev/null   # existing sub-folders too
done
setfacl -d -m o::--- "$d"
find "$d" -mindepth 1 -type d -exec setfacl -d -m o::--- {} + 2>/dev/null
exit 0
