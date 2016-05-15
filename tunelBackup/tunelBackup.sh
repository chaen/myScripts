#!/bin/bash
# christophe.haen@cern.ch

BRIDGE_USER=user1
BRIDGE_HOST=bidge.cern.ch
DST_HOST=pclhcb1234
DST_USER=user2
LOCAL_PORT=9000


DRY_RUN=true
EXCLUDE_PATTERN_FILE="./excludePattern.txt"
CONTROL_SOCKET="ctrl-socket"
BACKUP_LIST="./backupList.txt"

RSYNC_OPT="--recursive --verbose --compress --update --itemize-changes --progress"

DST_BASE_PATH="/tmp/extDD"

function usage(){
  echo "
    This script is used to backup folder through an ssh tunel.
    It opens an ssh tunel, reads the list of backup path from
    a file, and then close the tunel.
    Note that if the backup is stopped in the middle, you must close
    the tunel yourself.
    By default, the program runs in dry-mode, so it will not backup
    any data. See --force-run.
    It supports global exclusion pattern read from a file.
  "
  echo "
    Usage: $0 <options>
        -h,--help
		    Print this help
        -r,--force-run
		    Actually perform the backup, otherwise dry-run
        --bridge-user
		    User to use to connect to the bridge
        --bridge-host
		    Address of the bridge host
        --dst-user
		    User to use to connect to the final host
        --dst-host
		    Address of the final host
        --exclude-file
		    File which contains exclusion pattern for rsync. One pattern per line
        --no-exclude-file
		    Don't exclude anything 
        --backup-file
		    File which contains the list of path to backup. It is in the format
			  SrcA  DstA
			  SrcB  DstB
		    The destination pathes are prepended with the destination base path (see --dst-base-path).
			For example:
			  /localdisk/Documents/Images  MyPictures
		      will result in Images being synced in <dst-base-path>/MyPictures 

        --dst-base-path
		    Destination base path. Typically where the external hard drive would be mounted on the destination host
  "
  exit 0
}


OPTS=`getopt -o h,r -l bridge-user:,bridge-host:,dst-user:,dst-host,force-run,help,exclude-file:,no-exclude-file,backup-list:,dst-base-path: -- "$@"`
if [ $? != 0 ]
then
    exit 1
fi

eval set -- "$OPTS"

while true ; do
    case "$1" in
        -h|--help)
          usage;
          shift;;
        -r|--force-run)
          DRY_RUN=false;
          shift;;
        --bridge-user)
          BRIDGE_USER=$2;
          shift 2;;
        --bridge-host)
          BRIDGE_HOST=$2;
          shift 2;;
        --dst-user)
          DST_USER=$2;
          shift 2;;
        --dst-host)
          DST_HOST=$2;
          shift 2;;
        --exclude-file)
          EXCLUDE_PATTERN_FILE=$2;
          shift 2;;
        --no-exclude-file)
		  EXCLUDE_PATTERN_FILE=""
          shift ;;
        --backup-file)
          BACKUP_LIST=$2;
          shift 2;;
        --dst-base-path)
          DST_BASE_PATH=$2;
          shift 2;;
        --) shift; break;;
    esac
done

if [ "$DRY_RUN" = true ];
then
  echo "WARNING: dry run ! Will not copy anything";
  RSYNC_OPT="$RSYNC_OPT --dry-run";
else
  echo "WARNING: will run for good!";
fi

# Test if we use an exclusion pattern file, and if yes, if it exists

if [ -n "$EXCLUDE_PATTERN_FILE" ];
then
  if [ ! -e "$EXCLUDE_PATTERN_FILE" ];
  then
    echo "ERROR: exclusion pattern file $EXCLUDE_PATTERN_FILE does not exit";
    exit 2;
  else
    echo "INFO: Using exclusion pattern file $EXCLUDE_PATTERN_FILE";
    RSYNC_OPT="$RSYNC_OPT --exclude-from=$EXCLUDE_PATTERN_FILE";
  fi
else
  echo "INFO: not using any exclusion pattern !"
fi

if [ ! -e "$BACKUP_LIST" ];
then
  echo "ERROR: Backup file $BACKUP_LIST file does not exist";
  exit 2;
fi

echo "===== SUMMARY ====="
echo "  Exclusion pattern file: $EXCLUDE_PATTERN_FILE"
echo "  Backup path file: $BACKUP_LIST"
echo "  Bridge host: $BRIDGE_HOST"
echo "  Bridge user: $BRIDGE_USER"
echo "  Destination host: $DST_HOST"
echo "  Destination user: $DST_USER"
echo "  Destination base path: $DST_BASE_PATH"
echo "  Dry run: $DRY_RUN"
echo
echo

echo "Establishing bridge connection"
ssh -M -S $CONTROL_SOCKET -fnNT -L $LOCAL_PORT:$DST_HOST:22 $BRIDGE_USER@$BRIDGE_HOST

echo "Checking bridge connection (In case of crash, you have to close it yourself !!!"

ssh -S $CONTROL_SOCKET -O check $BRIDGE_USER@$BRIDGE_HOST

echo "Performing backup"
while read -r line || [[ -n "$line" ]]; do
  echo "Backing up: $line"
  read -a array <<< $line
  srcPath=${array[0]}
  dstPath="$DST_BASE_PATH"/${array[1]}
  echo "  Source $srcPath"
  echo "  Dst $dstPath"
  rsync $RSYNC_OPT  -e "ssh -p $LOCAL_PORT" $srcPath $DST_USER@localhost:$dstPath
done < $BACKUP_LIST




#ssh -S $CONTROL_SOCKET -O check $BRIDGE_USER@$BRIDGE_HOST
echo "Closing socket"
ssh -S $CONTROL_SOCKET -O exit $BRIDGE_USER@$BRIDGE_HOST
