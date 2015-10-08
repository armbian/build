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
	display_alert "Image size too small." "" "err"
	echo -e "[\e[0;31m Error \x1B[0m] Image size too small."
	exit
fi

# create needed directories and mount image to next free loop device
rm -rf $DEST/cache/sdcard/
mkdir -p $DEST/cache/rootfs $DEST/cache/sdcard

cd $DEST/cache

# We need to re-calculate from human to machine 
BOOTSTART=$(($OFFSET*2048))
ROOTSTART=$(($BOOTSTART+($BOOTSIZE*2048)))
BOOTEND=$(($ROOTSTART-1))

# Display what we do
display_alert "Creating blank image" "$SDSIZE Mb" "info"
if [ "$BOOTSIZE" -ne "0" ]; then 
	display_alert "Creating FAT boot partition" "$BOOTSIZE Mb" "info"
fi
# Create image file
while read line;do
  [[ "$line" =~ "records out" ]] &&
  echo "$(( ${line%+*}*100/$SDSIZE +1 ))" | dialog --gauge "Creating blank image ($SDSIZE Mb), please wait ..." 10 70
done< <( dd if=/dev/zero of=$DEST/cache/tmprootfs.raw bs=1M count=$SDSIZE 2>&1 &
         pid=$!
         sleep 1
         while kill -USR1 $pid 2>/dev/null;do
           sleep 1
         done )

# Find first available free device
LOOP=$(losetup -f)

if [[ "$LOOP" != "/dev/loop0" && "$LOOP" != "/dev/loop1" ]]; then
display_alert "You run out of loop devices" "pleese reboot" "error"
exit
fi

# Mount image as block device
losetup $LOOP $DEST/cache/tmprootfs.raw
sync

# Create partitions and file-system
parted -s $LOOP -- mklabel msdos
if [ "$BOOTSIZE" -eq "0" ]; then 
	parted -s $LOOP -- mkpart primary ext4  $ROOTSTART"s" -1s
	partprobe $LOOP
	mkfs.ext4 -q $LOOP"p1"
	mount $LOOP"p1" $DEST/cache/sdcard/
else
	parted -s $LOOP -- mkpart primary fat16  $BOOTSTART"s" $BOOTEND"s"
	parted -s $LOOP -- mkpart primary ext4  $ROOTSTART"s" -1s
	partprobe $LOOP
	mkfs.vfat -n "$IMAGEVOLUME" $LOOP"p1" >/dev/null 2>&1
	mkfs.ext4 -q $LOOP"p2"
	mount $LOOP"p2" $DEST/cache/sdcard/
	mkdir -p $DEST/cache/sdcard/boot
	mount $LOOP"p1" $DEST/cache/sdcard/boot
fi

# Uncompress from cache
if [ -f "$DEST/cache/rootfs/$RELEASE.tgz" ]; then
	filemtime=`stat -c %Y $DEST/cache/rootfs/$RELEASE.tgz`
	currtime=`date +%s`
	diff=$(( (currtime - filemtime) / 86400 ))
	display_alert "Extracting $RELEASE from cache" "$diff days old" "info"
	tar xpfz "$DEST/cache/rootfs/$RELEASE.tgz" -C $DEST/cache/sdcard/
	if [ "$diff" -gt "1" ]; then
		chroot $DEST/cache/sdcard /bin/bash -c "apt-get update" | dialog --progressbox "Force package update ..." 20 70
	fi
fi

# If we don't have a filesystem cached, let's make em
if [ ! -f "$DEST/cache/rootfs/$RELEASE.tgz" ]; then

# debootstrap base system
if [[ $RELEASE == "jessie" ]]; then sysvinit=",sysvinit-core"; fi
debootstrap --include=openssh-server,debconf-utils$sysvinit --arch=armhf --foreign $RELEASE $DEST/cache/sdcard/ | dialog --progressbox "Debootstrap $DISTRIBUTION $RELEASE base system to image template ..." 20 70

# remove systemd default load. It's installed and can be used with kernel parameter
if [[ $RELEASE == "jessie" ]]; then
sed -i -e 's/systemd-sysv //g' $DEST/cache/sdcard/debootstrap/required
fi

# we need emulator for second stage
cp /usr/bin/qemu-arm-static $DEST/cache/sdcard/usr/bin/

# and keys
d=$DEST/cache/sdcard/usr/share/keyrings/
test -d "$d" || mkdir -p "$d" && cp /usr/share/keyrings/debian-archive-keyring.gpg "$d" 

# enable arm binary format so that the cross-architecture chroot environment will work
test -e /proc/sys/fs/binfmt_misc/qemu-arm || update-binfmts --enable qemu-arm

# debootstrap second stage
chroot $DEST/cache/sdcard /bin/bash -c "/debootstrap/debootstrap --second-stage" | dialog --progressbox "Installing $DISTRIBUTION $RELEASE base system to image template ..." 20 70

# mount proc, sys and dev
mount -t proc chproc $DEST/cache/sdcard/proc
mount -t sysfs chsys $DEST/cache/sdcard/sys
mount -t devtmpfs chdev $DEST/cache/sdcard/dev || mount --bind /dev $DEST/cache/sdcard/dev
mount -t devpts chpts $DEST/cache/sdcard/dev/pts

# choose proper apt list
cp $SRC/lib/config/sources.list.$RELEASE $DEST/cache/sdcard/etc/apt/sources.list

# add armbian key
echo "deb http://apt.armbian.com $RELEASE main" > $DEST/cache/sdcard/etc/apt/sources.list.d/armbian.list
cp $SRC/lib/bin/armbian.key $DEST/cache/sdcard 
chroot $DEST/cache/sdcard /bin/bash -c "cat armbian.key | apt-key add -"
rm $DEST/cache/sdcard/armbian.key

# update and upgrade
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y update" | dialog --progressbox "Updating package databases ..." 20 70

# install aditional packages
PAKETKI="alsa-utils automake btrfs-tools bash-completion bc bridge-utils bluez build-essential cmake cpufrequtils curl \
device-tree-compiler dosfstools evtest figlet fbset fping git haveged hddtemp hdparm hostapd htop i2c-tools ifenslave-2.6 \
iperf ir-keytable iotop iozone3 iw less libbluetooth-dev libbluetooth3 libtool libwrap0-dev libfuse2 libssl-dev lirc lsof makedev \
module-init-tools mtp-tools nano ntfs-3g ntp parted pkg-config pciutils pv python-smbus rfkill rsync screen stress sudo subversion \
sysfsutils toilet u-boot-tools unattended-upgrades unzip usbutils vlan wireless-tools weather-util weather-util-data wget \
wpasupplicant iptables dvb-apps libdigest-sha-perl libproc-processtable-perl w-scan apt-transport-https"

# generate locales and install packets
display_alert "Install locales" "$DEST_LANG" "info"
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y -qq install locales"
if [ -f $DEST/cache/sdcard/etc/locale.gen ]; then sed -i "s/^# $DEST_LANG/$DEST_LANG/" $DEST/cache/sdcard/etc/locale.gen; fi
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/cache/sdcard /bin/bash -c "locale-gen $DEST_LANG"
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/cache/sdcard /bin/bash -c "export CHARMAP=$CONSOLE_CHAR FONTFACE=8x16 LANG=$DEST_LANG LANGUAGE=$DEST_LANG DEBIAN_FRONTEND=noninteractive"
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/cache/sdcard /bin/bash -c "update-locale LANG=$DEST_LANG LANGUAGE=$DEST_LANG LC_MESSAGES=POSIX"


install_packet "$PAKETKI" "Installing Armbian on the top of $DISTRIBUTION $RELEASE base system ..."

install_packet "console-setup console-data kbd console-common unicode-data" "Installing console packages"


# configure the system for unattended upgrades
cp $SRC/lib/scripts/50unattended-upgrades $DEST/cache/sdcard/etc/apt/apt.conf.d/50unattended-upgrades
cp $SRC/lib/scripts/02periodic $DEST/cache/sdcard/etc/apt/apt.conf.d/02periodic
sed -e "s/CODENAME/$RELEASE/g" -i $DEST/cache/sdcard/etc/apt/apt.conf.d/50unattended-upgrades

# copy hostapd configurations
install -m 755 $SRC/lib/config/hostapd.conf $DEST/cache/sdcard/etc/hostapd.conf 
install -m 755 $SRC/lib/config/hostapd.realtek.conf $DEST/cache/sdcard/etc/hostapd.conf-rt

# set up 'apt
cat <<END > $DEST/cache/sdcard/etc/apt/apt.conf.d/71-no-recommends
APT::Install-Recommends "0";
APT::Install-Suggests "0";
END

# console fix due to Debian bug 
sed -e 's/CHARMAP=".*"/CHARMAP="'$CONSOLE_CHAR'"/g' -i $DEST/cache/sdcard/etc/default/console-setup

# root-fs modifications
rm 	-f $DEST/cache/sdcard/etc/motd
touch $DEST/cache/sdcard/etc/motd

chroot $DEST/cache/sdcard /bin/bash -c "apt-get clean"
chroot $DEST/cache/sdcard /bin/bash -c "sync"
chroot $DEST/cache/sdcard /bin/bash -c "unset DEBIAN_FRONTEND"
sync
sleep 3
# unmount proc, sys and dev from chroot
umount -l $DEST/cache/sdcard/dev/pts
umount -l $DEST/cache/sdcard/dev
umount -l $DEST/cache/sdcard/proc
umount -l $DEST/cache/sdcard/sys

# kill process inside
KILLPROC=$(ps -uax | pgrep ntpd |        tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi  
KILLPROC=$(ps -uax | pgrep dbus-daemon | tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi  

display_alert "Closing deboostrap process and preparing cache." "" "info"

tar czpf $DEST/cache/rootfs/$RELEASE.tgz --directory=$DEST/cache/sdcard/ \
--exclude=dev/* --exclude=proc/* --exclude=run/* --exclude=tmp/* --exclude=mnt/* .
fi
#
# mount proc, sys and dev
mount -t proc chproc $DEST/cache/sdcard/proc
mount -t sysfs chsys $DEST/cache/sdcard/sys
mount -t devtmpfs chdev $DEST/cache/sdcard/dev || mount --bind /dev $DEST/cache/sdcard/dev
mount -t devpts chpts $DEST/cache/sdcard/dev/pts
}