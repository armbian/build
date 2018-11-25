#!/bin/sh

echo "Start script create MBR and filesystem"

if grep /dev/mmcblk0 /proc/mounts | grep "boot" ; then
    DEV_EMMC=/dev/mmcblk1
else
    DEV_EMMC=/dev/mmcblk0
fi

echo $DEV_EMMC

echo "Start backup u-boot default"

dd if="${DEV_EMMC}" of=/boot/u-boot-default.img bs=1M count=16

echo "Start create MBR and partittion"

parted -s "${DEV_EMMC}" mklabel msdos
parted -s "${DEV_EMMC}" mkpart primary fat32 16M 144M
parted -s "${DEV_EMMC}" mkpart primary ext4 145M 100%

echo "Start restore u-boot"

if [ -f /boot/uboot.img ] ; then
    dd if=/boot/uboot.img of="${DEV_EMMC}" conv=fsync seek=16384
fi

sync

echo "Done"

exit 0
