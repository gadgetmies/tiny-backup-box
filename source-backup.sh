LOG_FILE=${:-"/var/log/tiny-backup-box.log"}

# Back up previous log file
mv $LOG_FILE $LOG_FILE.old || true

echo "### Starting SD card backup at $(date)" | tee -a $LOG_FILE

cat << EOF
Using configuration:
-------------------
Storage mount point: $STORAGE_MOUNT_POINT
Storage device: $STORAGE_DEV

Source mount point: $SOURCE_MOUNT_POINT
Source device: $SOURCE_DEV

Log: $LOG_FILE

Power off after backup: $POWER_OFF
Stop LUCI while backing up: $STOP_LUCI_FOR_BACKUP

Status LED: $STATUS_LED
-------------------
EOF

mkdir -p $STORAGE_MOUNT_POINT
mkdir -p $SOURCE_MOUNT_POINT

echo "default-on" > /sys/class/leds/$STATUS_LED/trigger

MOUNTED_STORAGE=`findmnt -rno SOURCE $STORAGE_MOUNT_POINT`
if [ -z "$MOUNTED_STORAGE" ]; then
  echo "Storage device not mounted, start polling..."

	until [[ -e "$STORAGE_DEV" ]]; do
		sleep 1
	done

  echo "Found storage device in $STORAGE_DEV. Mounting to $STORAGE_MOUNT_POINT"
	mount "$STORAGE_DEV" "$STORAGE_MOUNT_POINT"
else
  echo "Storage device already mounted, continuing"
  STORAGE_DEV="$MOUNTED_STORAGE"
fi

MOUNTED_SOURCE=`findmnt -rno SOURCE $SOURCE_MOUNT_POINT`
if [ -z "$MOUNTED_SOURCE" ]; then
	echo "SD card not mounted, start polling..."

	until [[ -e "$SOURCE_DEV" ]]; do
		sleep 1
	done

	echo "Found SD card device in $SOURCE_DEV. Mounting to $SOURCE_MOUNT_POINT"
	mount "$SOURCE_DEV" "$SOURCE_MOUNT_POINT"
else
	echo "SD card already mounted, continuing"
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

if [ $STOP_LUCI_FOR_BACKUP = true ]; then
    echo "Stopping LUCI to free resources"
    /etc/init.d/uhttpd stop
    echo "LUCI stopped"
fi

echo "Starting backup at $(date)"

echo "heartbeat" > /sys/class/leds/$STATUS_LED/trigger

# The RP-WD03 can easily run out of memory crashing the backup. Thus loop until the backup is successful.
EXIT_CODE=1
while [ ! $EXIT_CODE = 0 ]
do
    RSYNC_OUTPUT=$(rsync -avhW --stats --exclude "*.id" --log-file="$LOG_FILE" "$SOURCE_MOUNT_POINT"/ "$BACKUP_PATH")
    EXIT_CODE=$?
    if [ ! $EXIT_CODE = 0 ]; then
      echo "Backup failed, restarting backup"
    fi
    sleep 1
done

echo "Backup done at $(date)"

if [ $STOP_LUCI_FOR_BACKUP = true ]; then
    echo "Starting LUCI"
    /etc/init.d/uhttpd start
    echo "LUCI started"
fi

echo "Unmounting SD card"
umount "$SOURCE_MOUNT_POINT"

if [ $UNMOUNT_STORAGE = true ]; then
  umount "$STORAGE_MOUNT_POINT"
fi

echo "none" > /sys/class/leds/$STATUS_LED/trigger

# Power off
if [ $POWER_OFF = true ]; then
	echo "Shutting down"
	poweroff
else
  echo "default-on" > /sys/class/leds/$STATUS_LED/trigger
  until [[ ! -e "$SOURCE_DEV" ]]; do
    echo "Waiting for SD card removal..."
    sleep 30
  done

  echo "SD card removed, restarting backup script"
fi
