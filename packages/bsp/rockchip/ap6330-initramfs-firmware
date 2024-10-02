#!/bin/sh -e

# Broadcom 4330 initramfs support file
# To let the kernel btbcm driver find the driver, we need to copy the 4330 firmware
# appropriately in the /lib/firmware/brcm directory of the initramfs. This script
# does that on each update.

if [ "$1" = "prereqs" ]; then exit 0; fi
. /usr/share/initramfs-tools/hook-functions

mkdir -p $DESTDIR/lib/firmware/brcm
cp /lib/firmware/brcm/BCM4330B1.hcd $DESTDIR/lib/firmware/brcm
