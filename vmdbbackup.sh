#!/bin/bash
#
# This script is intended to take periodic backups of the VMDB database
#

# Expected usage
# Place in crontab - example:
# 30 00 * * 6 /root/vmdbbackup.sh >/dev/null 2>&1 #weekly vmdb backup


# Function: f_CheckMount
# Arguments: 
#  Takes device name/path and mount point as single strings
# Action: 
#  Returns 0 if mounted
#  Returns 1 if not mounted
f_CheckMount() {

   DEV=$1
   MP=$2

   if [[ -n $(df -hP | grep "^${DEV}" | awk '{print $NF}' | grep "^${MP}$") ]]; then
      return 0
   else
      return 1
   fi
}

#Source root user's rofile
. /root/.bash_profile

# Define Variables
NFS_SERVER=nfs.nas.customer.corp
NFS_EXPORT=/path/on/nfs_server/cloudforms_backup
NFS_OPTIONS="-o vers=4.0"
NFS_MOUNT_POINT=$(mktemp -d)
NFS_URI="${NFS_SERVER}:${NFS_EXPORT}"
LOG="${NFS_MOUNT_POINT}/vmdb_backup_log.latest"

# Define Actions
MOUNT_BKDIR="mount $NFS_OPTIONS $NFS_URI $NFS_MOUNT_POINT"
UMOUNT_BKDIR="umount $NFS_MOUNT_POINT"

# Determine Backup Target Name
#TS=$(date +%d%m%Y)
#TS=$(date +%Y%m%d%H%M%S%Z)
TS=$(date +%Y-%m-%d_%H:%M:%S_%Z)
BKUP_TARGET="${NFS_MOUNT_POINT}/vmdb_backup.${TS}"


# Create the backup directory if it doesn't exist
if [[ ! -d "$NFS_MOUNT_POINT" ]]; then mkdir -p "$NFS_MOUNT_POINT"; fi

# Mount the backup directory if it isn't already mounted
f_CheckMount $NFS_URI $NFS_MOUNT_POINT
if [[ $? != 0 ]]; then
   $MOUNT_BKDIR
fi

# Pop smoke if the backup directory is not mounted
f_CheckMount $NFS_URI $NFS_MOUNT_POINT
if [[ $? != 0 ]]; then
   echo "Unable to mount backup directory, aborting DB Backup."
   exit 1
fi

# Create the backup 
pg_dump -v -Z 9 -F custom -h localhost -p 5432 -U root -w -f "${BKUP_TARGET}" vmdb_production >$LOG 2>&1

# Mail the backup log if desired
#if [[ $? -eq 0 ]]; then
#   /usr/bin/tail $LOG | /usr/bin/mail -s "vmdb backup Successful :`hostname`" name@domain.com
#else
#   /usr/bin/tail $LOG | /usr/bin/mailx -s "vmdb backup Failed :`hostname`" name@domain.com
#fi

# Rotate files over 10 days old
find ${NFS_MOUNT_POINT}/vmdb* -mtime +10 -exec rm {} \;

# Unmount the backup directory
$UMOUNT_BKDIR
f_CheckMount $NFS_URI $NFS_MOUNT_POINT
if [[ $? != 0 ]]; then
   # Remove the temporary mount point
   if [[ -d $NFS_MOUNT_POINT ]]; then
      rmdir $NFS_MOUNT_POINT
   fi
fi

exit 0

