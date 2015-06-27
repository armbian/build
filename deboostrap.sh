#!/bin/bash
#
# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of tool chain https://github.com/igorpecovnik/lib
#

custom_debootstrap (){
#--------------------------------------------------------------------------------------------------------------------------------
# Create clean and fresh Debian and Ubuntu image template if it does not exists
#--------------------------------------------------------------------------------------------------------------------------------

# is boot partition to big?
if [ "$SDSIZE" -le "$(($OFFSET+$BOOTSIZE))" ]; then 
	echo -e "[\e[0;31m Error \x1B[0m] Image size too small."
	exit
fi

# close loops
x=$(losetup -a |awk '{ print $1 }' | rev | cut -c 2- | rev | tac);
for x in $x; do
	losetup -d $x;
done

cd $DEST/output

# create needed directories and mount image to next free loop device
rm -rf $DEST/output/sdcard/
mkdir -p $DEST/output/rootfs $DEST/output/sdcard $DEST/output/kernel

# We need to re-calculate from human to machine 
BOOTSTART=$(($OFFSET*2048))
ROOTSTART=$(($BOOTSTART+($BOOTSIZE*2048)))
BOOTEND=$(($ROOTSTART-1))

# Display what we do
echo -en "[\e[0;32m ok \x1B[0m] Creating\e[0;32m $SDSIZE Mb\x1B[0m SD card image with\e[0;32m $OFFSET Mb\x1B[0m reservation for u-boot"
if [ "$BOOTSIZE" -ne "0" ]; then 
	echo -e " and\e[0;32m $BOOTSIZE Mb\x1B[0m for FAT boot file-system."
fi
# Create image file
dd if=/dev/zero of=$DEST/output/tmprootfs.raw bs=1M count=$SDSIZE status=noxfer >/dev/null 2>&1

# Find first available free device
LOOP=$(losetup -f)

# Mount image as block device
losetup $LOOP $DEST/output/tmprootfs.raw
sync

# Create partitions and file-system
parted -s $LOOP -- mklabel msdos
if [ "$BOOTSIZE" -eq "0" ]; then 
	parted -s $LOOP -- mkpart primary ext4  $ROOTSTART"s" -1s
	partprobe $LOOP
	mkfs.ext4 -q $LOOP"p1"
	mount $LOOP"p1" $DEST/output/sdcard/
else
	parted -s $LOOP -- mkpart primary fat16  $BOOTSTART"s" $BOOTEND"s"
	parted -s $LOOP -- mkpart primary ext4  $ROOTSTART"s" -1s
	partprobe $LOOP
	mkfs.vfat -n "$IMAGEVOLUME" $LOOP"p1" >/dev/null 2>&1
	mkfs.ext4 -q $LOOP"p2"
	mount $LOOP"p2" $DEST/output/sdcard/
	mkdir -p $DEST/output/sdcard/boot
	mount $LOOP"p1" $DEST/output/sdcard/boot
fi

# Uncompress from cache
if [ -f "$DEST/output/rootfs/$RELEASE.tgz" ]; then
	filemtime=`stat -c %Y $DEST/output/rootfs/$RELEASE.tgz`
	currtime=`date +%s`
	diff=$(( (currtime - filemtime) / 86400 ))
	echo -e ""
	echo -e "[\e[0;32m ok \x1B[0m] Extracting\e[0;32m $RELEASE\x1B[0m from cache. Your cache is\e[0;32m $diff\x1B[0m days old."
	tar xpfz "$DEST/output/rootfs/$RELEASE.tgz" -C $DEST/output/sdcard/
fi

# If we don't have a filesystem cached, let's make em

if [ ! -f "$DEST/output/rootfs/$RELEASE.tgz" ]; then
echo -e "[\e[0;32m ok \x1B[0m] Debootstrap $RELEASE to image template"

# debootstrap base system
debootstrap --include=openssh-server,debconf-utils --arch=armhf --foreign $RELEASE $DEST/output/sdcard/ 

# we need emulator for second stage
cp /usr/bin/qemu-arm-static $DEST/output/sdcard/usr/bin/

# enable arm binary format so that the cross-architecture chroot environment will work
test -e /proc/sys/fs/binfmt_misc/qemu-arm || update-binfmts --enable qemu-arm

# debootstrap second stage
chroot $DEST/output/sdcard /bin/bash -c "/debootstrap/debootstrap --second-stage"

# mount proc, sys and dev
mount -t proc chproc $DEST/output/sdcard/proc
mount -t sysfs chsys $DEST/output/sdcard/sys
mount -t devtmpfs chdev $DEST/output/sdcard/dev || mount --bind /dev $DEST/output/sdcard/dev
mount -t devpts chpts $DEST/output/sdcard/dev/pts

# choose proper apt list
cp $SRC/lib/config/sources.list.$RELEASE $DEST/output/sdcard/etc/apt/sources.list

# update and upgrade
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/output/sdcard /bin/bash -c "apt-get -y update"

# install aditional packages
PAKETKI="alsa-utils automake btrfs-tools bash-completion bc bridge-utils bluez build-essential cmake cpufrequtils curl \
device-tree-compiler dosfstools evtest figlet fbset fping git haveged hddtemp hdparm hostapd htop i2c-tools ifenslave-2.6 \
iperf ir-keytable iotop iw less libbluetooth-dev libbluetooth3 libtool libwrap0-dev libfuse2 libssl-dev lirc lsof makedev \
module-init-tools mtp-tools nano ntfs-3g ntp parted pkg-config pciutils pv python-smbus rfkill rsync screen stress sudo \
sysfsutils toilet u-boot-tools unattended-upgrades unzip usbutils vlan wireless-tools wget wpasupplicant"

# generate locales and install packets
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/output/sdcard /bin/bash -c "apt-get -y -qq install locales"
if [ -f $DEST/output/sdcard/etc/locale.gen ]; then sed -i "s/^# $DEST_LANG/$DEST_LANG/" $DEST/output/sdcard/etc/locale.gen; fi
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/output/sdcard /bin/bash -c "locale-gen $DEST_LANG"
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/output/sdcard /bin/bash -c "export CHARMAP=$CONSOLE_CHAR FONTFACE=8x16 LANG=$DEST_LANG LANGUAGE=$DEST_LANG DEBIAN_FRONTEND=noninteractive"
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/output/sdcard /bin/bash -c "update-locale LANG=$DEST_LANG LANGUAGE=$DEST_LANG LC_MESSAGES=POSIX"

chroot $DEST/output/sdcard /bin/bash -c "debconf-apt-progress -- apt-get -y install $PAKETKI"

# install console setup separate
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/output/sdcard /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y install \
console-setup console-data kbd console-common unicode-data"

# configure the system for unattended upgrades
cp $SRC/lib/scripts/50unattended-upgrades $DEST/output/sdcard/etc/apt/apt.conf.d/50unattended-upgrades
cp $SRC/lib/scripts/02periodic $DEST/output/sdcard/etc/apt/apt.conf.d/02periodic
sed -e "s/CODENAME/$RELEASE/g" -i $DEST/output/sdcard/etc/apt/apt.conf.d/50unattended-upgrades

# set up 'apt
cat <<END > $DEST/output/sdcard/etc/apt/apt.conf.d/71-no-recommends
APT::Install-Recommends "0";
APT::Install-Suggests "0";
END

# console fix due to Debian bug 
sed -e 's/CHARMAP=".*"/CHARMAP="'$CONSOLE_CHAR'"/g' -i $DEST/output/sdcard/etc/default/console-setup

# root-fs modifications
rm 	-f $DEST/output/sdcard/etc/motd
touch $DEST/output/sdcard/etc/motd

chroot $DEST/output/sdcard /bin/bash -c "apt-get clean"
chroot $DEST/output/sdcard /bin/bash -c "sync"
chroot $DEST/output/sdcard /bin/bash -c "unset DEBIAN_FRONTEND"
sync
sleep 3
# unmount proc, sys and dev from chroot
umount -l $DEST/output/sdcard/dev/pts
umount -l $DEST/output/sdcard/dev
umount -l $DEST/output/sdcard/proc
umount -l $DEST/output/sdcard/sys

# kill process inside
KILLPROC=$(ps -uax | pgrep ntpd |        tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi  
KILLPROC=$(ps -uax | pgrep dbus-daemon | tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi  
echo -e "[\e[0;32m ok \x1B[0m] Closing and preparing cache"
tar czpf $DEST/output/rootfs/$RELEASE.tgz --directory=$DEST/output/sdcard/ \
--exclude=dev/* --exclude=proc/* --exclude=run/* --exclude=tmp/* --exclude=mnt/* .
fi
#
# mount proc, sys and dev
mount -t proc chproc $DEST/output/sdcard/proc
mount -t sysfs chsys $DEST/output/sdcard/sys
mount -t devtmpfs chdev $DEST/output/sdcard/dev || mount --bind /dev $DEST/output/sdcard/dev
mount -t devpts chpts $DEST/output/sdcard/dev/pts
}