#!/bin/sh

echo "Start script create MBR and filesystem"

hasdrives=$(lsblk | grep -oE '(mmcblk[0-9])' | sort | uniq)
if [ "$hasdrives" = "" ]
then
	echo "UNABLE TO FIND ANY EMMC OR SD DRIVES ON THIS SYSTEM!!! "
	exit 1
fi
avail=$(lsblk | grep -oE '(mmcblk[0-9]|sda[0-9])' | sort | uniq)
if [ "$avail" = "" ]
then
	echo "UNABLE TO FIND ANY DRIVES ON THIS SYSTEM!!!"
	exit 1
fi

#unmount /var/log.hdd so logic below can find the root partition
umount /var/log.hdd

runfrom=$(lsblk | grep /$ | grep -oE '(mmcblk[0-9]|sda[0-9])')
if [ "$runfrom" = "" ]
then
	echo " UNABLE TO FIND ROOT OF THE RUNNING SYSTEM!!! "
	exit 1
fi
emmc=$(echo $avail | sed "s/$runfrom//" | sed "s/sd[a-z][0-9]//g" | sed "s/ //g")
if [ "$emmc" = "" ]
then
	echo " UNABLE TO FIND YOUR EMMC DRIVE OR YOU ALREADY RUN FROM EMMC!!!"
	exit 1
fi
if [ "$runfrom" = "$avail" ]
then
	echo " YOU ARE RUNNING ALREADY FROM EMMC!!! "
	exit 1
fi
if [ $runfrom = $emmc ]
then
	echo " YOU ARE RUNNING ALREADY FROM EMMC!!! "
	exit 1
fi
if [ "$(echo $emmc | grep mmcblk)" = "" ]
then
	echo " YOU DO NOT APPEAR TO HAVE AN EMMC DRIVE!!! "
	exit 1
fi

DEV_EMMC="/dev/$emmc"

echo $DEV_EMMC

echo "Start backup u-boot default"

dd if="${DEV_EMMC}" of=/root/u-boot-default-aml.img bs=1M count=4

echo "Start create MBR and partittion"

parted -s "${DEV_EMMC}" mklabel msdos
parted -s "${DEV_EMMC}" mkpart primary fat32 1000M 1512M
parted -s "${DEV_EMMC}" mkpart primary ext4 1513M 100%

echo "Start restore u-boot"

dd if=/root/u-boot-default-aml.img of="${DEV_EMMC}" conv=fsync bs=1 count=442
dd if=/root/u-boot-default-aml.img of="${DEV_EMMC}" conv=fsync bs=512 skip=1 seek=1

sync

echo "Done"

echo "Start copy system for eMMC."

mkdir -p /ddbr
chmod 777 /ddbr

PART_BOOT="${DEV_EMMC}p1"
PART_ROOT="${DEV_EMMC}p2"
DIR_INSTALL="/ddbr/install"

if [ -d $DIR_INSTALL ] ; then
    rm -rf $DIR_INSTALL
fi
mkdir -p $DIR_INSTALL

if grep -q $PART_BOOT /proc/mounts ; then
    echo "Unmounting BOOT partiton."
    umount -f $PART_BOOT
fi
echo -n "Formatting BOOT partition..."
mkfs.vfat -n "BOOT_EMMC" $PART_BOOT
echo "done."

mount -o rw $PART_BOOT $DIR_INSTALL

echo -n "Copying BOOT..."
cp -r /boot/* $DIR_INSTALL && sync
echo "done."

echo -n "Edit init config..."
sed -e "s/\(root=UUID\)\([[:graph:]]\)*/root=LABEL=ROOT_EMMC/gi" \
 -i "$DIR_INSTALL/extlinux/extlinux.conf"
echo "done."

rm $DIR_INSTALL/s9*
rm $DIR_INSTALL/aml*

if [ -f /boot/u-boot.ext ] ; then
    mv -f $DIR_INSTALL/u-boot.ext $DIR_INSTALL/u-boot.emmc

    sed -e "s/u-boot.ext/u-boot.emmc/g" \
     -i "$DIR_INSTALL/boot.ini"
    echo "done."

    sync
fi

umount $DIR_INSTALL

if grep -q $PART_ROOT /proc/mounts ; then
    echo "Unmounting ROOT partiton."
    umount -f $PART_ROOT
fi

echo "Formatting ROOT partition..."
mke2fs -F -q -t ext4 -L ROOT_EMMC -m 0 $PART_ROOT
e2fsck -n $PART_ROOT
echo "done."

echo "Copying ROOTFS."

mount -o rw $PART_ROOT $DIR_INSTALL

cd /
echo "Copy BIN"
tar -cf - bin | (cd $DIR_INSTALL; tar -xpf -)
#echo "Copy BOOT"
#mkdir -p $DIR_INSTALL/boot
#tar -cf - boot | (cd $DIR_INSTALL; tar -xpf -)
echo "Create DEV"
mkdir -p $DIR_INSTALL/dev
#tar -cf - dev | (cd $DIR_INSTALL; tar -xpf -)
echo "Copy ETC"
tar -cf - etc | (cd $DIR_INSTALL; tar -xpf -)
echo "Copy HOME"
tar -cf - home | (cd $DIR_INSTALL; tar -xpf -)
echo "Copy LIB"
tar -cf - lib | (cd $DIR_INSTALL; tar -xpf -)
echo "Copy LIB64"
tar -cf - lib64 | (cd $DIR_INSTALL; tar -xpf -)
echo "Create MEDIA"
mkdir -p $DIR_INSTALL/media
#tar -cf - media | (cd $DIR_INSTALL; tar -xpf -)
echo "Create MNT"
mkdir -p $DIR_INSTALL/mnt
#tar -cf - mnt | (cd $DIR_INSTALL; tar -xpf -)
echo "Copy OPT"
tar -cf - opt | (cd $DIR_INSTALL; tar -xpf -)
echo "Create PROC"
mkdir -p $DIR_INSTALL/proc
echo "Copy ROOT"
tar -cf - root | (cd $DIR_INSTALL; tar -xpf -)
echo "Create RUN"
mkdir -p $DIR_INSTALL/run
echo "Copy SBIN"
tar -cf - sbin | (cd $DIR_INSTALL; tar -xpf -)
echo "Copy SELINUX"
tar -cf - selinux | (cd $DIR_INSTALL; tar -xpf -)
echo "Copy SRV"
tar -cf - srv | (cd $DIR_INSTALL; tar -xpf -)
echo "Create SYS"
mkdir -p $DIR_INSTALL/sys
echo "Create TMP"
mkdir -p $DIR_INSTALL/tmp
echo "Copy USR"
tar -cf - usr | (cd $DIR_INSTALL; tar -xpf -)
echo "Copy VAR"
tar -cf - var | (cd $DIR_INSTALL; tar -xpf -)
sync

echo "Copy fstab"

rm $DIR_INSTALL/etc/fstab
cp -a /root/fstab.template $DIR_INSTALL/etc/fstab

rm $DIR_INSTALL/root/install*.sh
rm $DIR_INSTALL/root/fstab.template
rm $DIR_INSTALL/usr/bin/ddbr


cd /
sync

umount $DIR_INSTALL

echo "*******************************************"
echo "Complete copy OS to eMMC "
echo "*******************************************"
