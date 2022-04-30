#!/bin/sh
MAC=""

echo "Start script create MBR and filesystem"

INSTALL_PATH=/boot/install
#sh ${INSTALL_PATH}/update_led.sh &
if [ -e /dev/mmcblk0 ];then
    DEV=mmcblk0
else
    DEV=mmcblk1
fi

DEV_EMMC=/dev/${DEV}
DEV_BOOT0=${DEV_EMMC}boot0
DEV_BOOT1=${DEV_EMMC}boot1
BOOT0=${DEV}boot0
BOOT1=${DEV}boot1
PART_BOOT=${DEV_EMMC}p1
PART_ROOT=${DEV_EMMC}p2
UBOOT=${INSTALL_PATH}/u-boot.bin
ENV=${INSTALL_PATH}/env.img

rm -f /etc/machine-id
systemd-machine-id-setup

if [ -z "$MAC" ]; then
	MAC=$(dd if=/dev/urandom bs=1024 count=1 2>/dev/null | md5sum | sed -e 's/^\(..\)\(..\)\(..\)\(..\).*$/00:22:\1:\2:\3:\4/' -e 's/^\(.\)[13579bdf]/\10/')
	
	[ -f /opt/client.crt ] && {
	    MAC=$(openssl x509 -in /opt/client.crt -noout --text | grep "Subject:" | awk '{print $10}' | awk -F '[' '{print $2}' | awk -F ']' '{print $1}') 
	}
fi
echo "Create MAC: ${MAC}"

echo "Start create MBR and partittion"

parted -s "${DEV_EMMC}" mklabel msdos
parted -s "${DEV_EMMC}" mkpart primary fat32 108M 620M
parted -s "${DEV_EMMC}" mkpart primary ext4  724M 100%

echo "Start restore u-boot"

dd if=${UBOOT} of="${DEV_EMMC}" conv=fsync bs=1 count=442
dd if=${UBOOT} of="${DEV_EMMC}" conv=fsync bs=512 skip=1 seek=1
dd if=${ENV} of="${DEV_EMMC}" conv=fsync bs=1M seek=628 count=8

sync
echo "Done"

echo "Start copy system for eMMC."

mkdir -p /ddbr
chmod 777 /ddbr

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
cp -r /boot/* $DIR_INSTALL && cp -p $INSTALL_PATH/s805_autoscript* $DIR_INSTALLcp -p $INSTALL_PATH/uEnv.txt $DIR_INSTALL && sync
echo "done."

echo -n "Edit init config..."
sed -e "s/ROOTFS/ROOT_EMMC/g" \
 -i "$DIR_INSTALL/uEnv.txt"
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
cp -a ${INSTALL_PATH}/fstab $DIR_INSTALL/etc/fstab

echo "Change MAC"
cp -p $DIR_INSTALL/etc/network/interfaces.default $DIR_INSTALL/etc/network/interfaces
sed -i '/iface eth0 inet dhcp/a\hwaddress '${MAC} $DIR_INSTALL/etc/network/interfaces

cd /
sync

umount $DIR_INSTALL

echo "*******************************************"
echo "Complete copy OS to eMMC "
echo "*******************************************"

shutdown -h now
