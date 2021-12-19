# Tiny Backup Box
A tool for photo backup for devices running OpenWRT based on / inspired by the [Little Backup Box project](https://github.com/dmpop/little-backup-box/).

Unlike the Little Backup Box however, only the SD card to USB storage backup (i.e. source backup) option is currently implemented.

For (potentially) suitable hardware, take a look at the [OpenWRT Table of Hardware](https://openwrt.org/toh/views/toh_battery-powered?datasrt=usb+ports&dataflt%5BUSB+ports_*%7E%5D=1)

## Features
* Automatically and incremental SD card backup to prevent losing photos due to lost or damaged SD cards
* Ability to create a small, lightweight and portable backup solution suitable for travel use
* Fully customisable backup solution (at least to the extent enabled by the hardwire)

The scripts have been created and tested on the **Ravpower Filehub Plus (RP-WD03)** running the OpenWRT firmware, but should work also on other devices running OpenWRT (YMMV). In order to use the RP-WD03, you need to [install OpenWRT on the device](https://openwrt.org/toh/ravpower/rp-wd03#installation).

## Installation
**Warning! By following these instructions, you risk bricking your device and data loss on the storage devices. Proceed with caution! Also note that some knowledge of Linux devices and filesystems is required.**
1. Log in to your OpenWRT device via SSH as root
2. Download and modify the `install.sh` script to match your desired setup (storage devices, mount points, extroot setup etc.)
3. Make the install script executable: `chmod go+x install.sh`
4. Run the install script: `./install.sh`
5. Start backing up!
