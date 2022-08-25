echo "Starting SD card backup"

mkdir -p $STORAGE_MOUNT_POINT
mkdir -p $SOURCE_MOUNT_POINT

LOG_FILE=${LOG_FILE:-"/var/log/tiny-backup-box.log"}

MOUNTED_STORAGE=`findmnt -rno SOURCE $STORAGE_MOUNT_POINT`
if [ -z "$MOUNTED_STORAGE" ]; then
  echo "Storage device not mounted, start polling..." | tee -a $LOG_FILE

	until [[ -e "$STORAGE_DEV" ]]; do
		sleep 1
	done

  echo "Found storage device in $STORAGE_DEV. Mounting to $STORAGE_MOUNT_POINT" | tee -a $LOG_FILE
	mount "$STORAGE_DEV" "$STORAGE_MOUNT_POINT"
else
  echo "Storage device already mounted, continuing" | tee -a $LOG_FILE
  STORAGE_DEV="$MOUNTED_STORAGE"
fi

MOUNTED_SOURCE=`findmnt -rno SOURCE $SOURCE_MOUNT_POINT`
if [ -z "$MOUNTED_SOURCE" ]; then
	echo "SD card not mounted, start polling..." | tee -a $LOG_FILE

	until [[ -e "$SOURCE_DEV" ]]; do
		sleep 1
	done

	echo "Found SD card device in $SOURCE_DEV. Mounting to $SOURCE_MOUNT_POINT" | tee -a $LOG_FILE
	mount "$SOURCE_DEV" "$SOURCE_MOUNT_POINT"
else
	echo "SD card already mounted, continuing" | tee -a $LOG_FILE
  SOURCE_DEV="$MOUNTED_SOURCE"
fi

cd $SOURCE_MOUNT_POINT
if [ ! -f *.id ]; then
    random=$(</dev/urandom tr -dc A-Za-z0-9-_ | head -c 22)
    touch $(date +"%Y%m%d%H%M")-$random.id
fi
ID_FILE=$(ls -t *.id | head -n1)
ID="${ID_FILE%.*}"
cd

# Set the backup path
BACKUP_PATH="$STORAGE_MOUNT_POINT"/"$ID"

rm -f $LOG_FILE

if [ $STOP_LUCI_FOR_BACKUP = true ]; then
    echo "Stopping LUCI to free resources" | tee -a $LOG_FILE
    /etc/init.d/uhttpd stop
    echo "LUCI stopped" | tee -a $LOG_FILE
fi

echo "Starting backup at $(date)" | tee -a $LOG_FILE

# The RP-WD03 can easily run out of memory crashing the backup. Thus loop until the backup is successful.
EXIT_CODE=1
while [ ! $EXIT_CODE = 0 ]
do
    RSYNC_OUTPUT=$(rsync -avh --stats --exclude "*.id" --log-file="$LOG_FILE" "$SOURCE_MOUNT_POINT"/ "$BACKUP_PATH")
    EXIT_CODE=$?
    if [ ! $EXIT_CODE = 0 ]; then
      echo "Backup failed, restarting backup" | tee -a $LOG_FILE
    fi
    sleep 1
done

echo "Backup done at $(date)" | tee -a $LOG_FILE

if [ $STOP_LUCI_FOR_BACKUP = true ]; then
    echo "Starting LUCI" | tee -a $LOG_FILE
    /etc/init.d/uhttpd start
    echo "LUCI started" | tee -a $LOG_FILE
fi

echo "Unmounting SD card" | tee -a $LOG_FILE
umount "$SOURCE_MOUNT_POINT"

if [ $UNMOUNT_STORAGE = true ]; then
  umount "$STORAGE_MOUNT_POINT"
fi

# Power off
if [ $POWER_OFF = true ]; then
	echo "Shutting down" | tee -a $LOG_FILE
	poweroff
else
  until [[ ! -e "$SOURCE_DEV" ]]; do
    echo "Waiting for SD card removal..." | tee -a $LOG_FILE
    sleep 30
  done

  echo "SD card removed, restarting backup script" | tee -a $LOG_FILE
fi
