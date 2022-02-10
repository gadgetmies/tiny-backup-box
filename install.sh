# Before you start:
# Connect the backup device to the internet (also a good idea to connect it to a charger)
# Connect an external hard disk with a exFAT partition
# (To make an exFAT partition that mounts on MacOS, see second answer: https://unix.stackexchange.com/questions/460155/mac-os-cannot-mount-exfat-disk-created-on-ubuntu-linux)

# If you have a device with limited space, you might want to use a extroot setup (https://openwrt.org/docs/guide-user/additional-software/extroot_configuration)
# For this you need to have a device with an ext4 partition available.
# For example you could have a 1Tb SSD with 1G ext4 as the second partition (i.e. /dev/sdx2) and an exFAT partition
# taking up the rest of the space as the first partition (i.e. /dev/sdx1). The partitions are ordered in this manner
# for MacOS (perhaps also Windows?) to be able to read the exFAT partition.

STORAGE_DEV=/dev/sda1
STORAGE_MOUNT_POINT=/mnt/storage
SOURCE_DEV=/dev/sdb1
SOURCE_MOUNT_POINT=/mnt/source
OVERLAY_DEV=/dev/sda2 # Remove this if you have already set up an extroot (e.g. by running this script) or if you do not need the extroot setup

CHECK_STORAGE_ON_BOOT=true
SERVICE_LOG_FILE=/var/log/tiny-backup-box.log

opkg update
opkg install block-mount kmod-usb-storage mount-utils

OVERLAY_CONFIG="$(uci show fstab.overlay)"
if [[ -z "$OVERLAY_SETUP" ]] && [ ! -z "$OVERLAY_DEV" ]; then
  # Install extroot
  opkg install kmod-fs-ext4 e2fsprogs

  # Configure /etc/config/fstab to mount the rootfs_data in another directory in case you need to access the original
  # root overlay to change your extroot settings

  DEVICE="$(sed -n -e "/\s\/overlay\s.*$/s///p" /etc/mtab)"
  uci -q delete fstab.rwm
  uci set fstab.rwm="mount"
  uci set fstab.rwm.device="${DEVICE}"
  uci set fstab.rwm.target="/rwm"
  uci commit fstab

  # The directory /rwm will contain the original root overlay, which is used as the main root overlay until the extroot
  # is up and running. Later you can edit /rwm/upper/etc/config/fstab to change your extroot configuration (or temporarily
  # disable it) should you ever need to.

  # Now we configure the selected partition as new overlay via fstab UCI subsystem:
  eval $(block info ${OVERLAY_DEV} | grep -o -e "UUID=\S*")
  uci -q delete fstab.overlay
  uci set fstab.overlay="mount"
  uci set fstab.overlay.uuid="${UUID}"
  uci set fstab.overlay.target="/overlay"
  uci commit fstab

  # We now transfer the content of the current overlay inside the external drive and reboot the device to apply changes:
  mkdir -p /tmp/cproot
  mount --bind /overlay /tmp/cproot
  mount ${DEVICE} /mnt
  tar -C /tmp/cproot -cvf - . | tar -C /mnt -xf -
  umount /tmp/cproot /mnt
  echo "Extroot set up complete, rebooting. Rerun the script after boot to continue the setup."
  sleep 5
  reboot
fi

opkg update
opkg install kmod-fs-exfat kmod-fs-vfat libblkid

# Make the storage disk automount.
mkdir -p $STORAGE_MOUNT_POINT
eval $(block info ${STORAGE_DEV} | grep -o -e "UUID=\S*")
uci -q delete fstab.storage
uci set fstab.storage="mount"
uci set fstab.storage.uuid="${UUID}"
uci set fstab.storage.target="${SOURCE_MOUNT_POINT}"
uci set fstab.storage.enabled='1'

if [ "$CHECK_STORAGE_ON_BOOT" = true ]; then
  uci set fstab.storage.check_fs='1'
fi

uci commit fstab
service fstab boot

# Install the tools and services needed for the backup
opkg install rsync

cat <<"EOF" >/etc/init.d/tiny-backup-box
#!/bin/sh /etc/rc.common

USE_PROCD=1
START=99
STOP=1
SCRIPT=/root/source-backup.sh

start_service() {
  local env

  procd_open_instance

  config_cb() {
    option_cb() {
      env="$env $1=$2"
    }
  }

  config_load tiny-backup-box

  procd_set_param env $env
  procd_set_param command /bin/sh "${SCRIPT}"
  procd_set_param stdout 1 # forward stdout of the command to logd
  procd_set_param stderr 1 # same for stderr
  procd_set_param respawn ${respawn_threshold:-3600} ${respawn_timeout:-5} ${respawn_retry:-5}
  procd_close_instance
}
EOF

echo 'config main main' >/etc/config/tiny-backup-box
echo '  option STORAGE_DEV "$STORAGE_DEV" # Name of the storage device' >>/etc/config/tiny-backup-box
echo '  option STORAGE_MOUNT_POINT "$STORAGE_MOUNT_POINT" # Mount point of the storage device' >>/etc/config/tiny-backup-box
echo '  option SOURCE_DEV "$SOURCE_DEV" # Name of the source device' >>/etc/config/tiny-backup-box
echo '  option SOURCE_MOUNT_POINT "$SOURCE_MOUNT_POINT" # Mount point of the source device' >>/etc/config/tiny-backup-box
echo '  option POWER_OFF true # Set to false to disable automatic power off after backup' >>/etc/config/tiny-backup-box
echo '  option UNMOUNT_STORAGE true # Set to true to unmount storage device after backup' >>/etc/config/tiny-backup-box
echo '  option STOP_LUCI_FOR_BACKUP true # Stop LUCI while running backup to free memory' >>/etc/config/tiny-backup-box
echo '  option LOG_FILE "$SERVICE_LOG_FILE" # Log file location. The backup process will be reported here' >>/etc/config/tiny-backup-box

/etc/init.d/tiny-backup-box enable
/etc/init.d/tiny-backup-box start
