#!/bin/sh

echo "Start copy system for eMMC."

mkdir -p /ddbr
chmod 777 /ddbr

if grep /dev/mmcblk0 /proc/mounts | grep "boot" ; then
    PART_BOOT="/dev/mmcblk1p1"
    PART_ROOT="/dev/mmcblk1p2"
else
    PART_BOOT="/dev/mmcblk0p1"
    PART_ROOT="/dev/mmcblk0p2"
fi

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

echo -n "Cppying BOOT..."
cp -r /boot/* $DIR_INSTALL && sync
echo "done."

echo -n "Edit init config..."
sed -e "s/ROOTFS/ROOT_EMMC/g" \
 -i "$DIR_INSTALL/extlinux/extlinux.conf"
echo "done."

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

echo "Copy fstab"

rm $DIR_INSTALL/etc/fstab
cp -a /root/fstab $DIR_INSTALL/etc/fstab

rm $DIR_INSTALL/root/install.sh
rm $DIR_INSTALL/root/fstab
rm $DIR_INSTALL/usr/bin/ddbr

sync
umount $DIR_INSTALL

echo "*******************************************"
echo "Complete copy OS to eMMC "
echo "*******************************************"
