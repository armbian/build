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
#
# Functions:
# custom_debootstrap
#

custom_debootstrap (){
#---------------------------------------------------------------------------------------------------------------------------------
# Create clean and fresh Debian and Ubuntu image template if it does not exists
#---------------------------------------------------------------------------------------------------------------------------------

# is boot partition to big?
#if [ "$SDSIZE" -le "$(($OFFSET+$BOOTSIZE))" ]; then
#	display_alert "Image size too small." "$BOOTSIZE > $SDSIZE" "err"
#	exit
#fi

# create needed directories and mount image to next free loop device
rm -rf $DEST/cache/sdcard/
mkdir -p $DEST/cache/rootfs $DEST/cache/sdcard

cd $DEST/cache

# We need to re-calculate from human to machine 
BOOTSTART=$(($OFFSET*2048))
ROOTSTART=$(($BOOTSTART+($BOOTSIZE*2048)))
BOOTEND=$(($ROOTSTART-1))

# Create image file

if [ "$OUTPUT_DIALOG" = "yes" ]; then
	(dd if=/dev/zero bs=1M status=none count=$SDSIZE | pv -n -s $(( $SDSIZE * 1024 * 1024 )) | dd status=none of=$DEST/cache/tmprootfs.raw) 2>&1 \
	| dialog --backtitle "$backtitle" --title "Creating blank image ($SDSIZE), please wait ..." --gauge "" 5 70
else
	dd if=/dev/zero bs=1M status=none count=$SDSIZE | pv -p -b -r -s $(( $SDSIZE * 1024 * 1024 )) | dd status=none of=$DEST/cache/tmprootfs.raw
fi

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

# rootfs cache file name
[[ $BUILD_DESKTOP == yes ]] && local variant_desktop=yes
local cache_fname="$DEST/cache/rootfs/$RELEASE${variant_desktop:+_desktop}.tgz"

# Uncompress from cache
if [ -f "$cache_fname" ]; then
	filemtime=`stat -c %Y $cache_fname`
	currtime=`date +%s`
	diff=$(( (currtime - filemtime) / 86400 ))
	display_alert "Extracting $RELEASE from cache" "$diff days old" "info"
	pv -p -b -r -c -N "$cache_fname" "$cache_fname" | pigz -dc | tar xp -C $DEST/cache/sdcard/
	if [ "$diff" -gt "3" ]; then
		chroot $DEST/cache/sdcard /bin/bash -c "apt-get update" | dialog --backtitle "$backtitle" --title "Force package update ..." --progressbox 20 70
	fi
fi

# If we don't have a filesystem cached, let's make em
if [ ! -f "$cache_fname" ]; then

# debootstrap base system
debootstrap --include=openssh-server,debconf-utils --arch=armhf --foreign $RELEASE $DEST/cache/sdcard/ | dialog --backtitle "$backtitle" --title "Debootstrap $DISTRIBUTION $RELEASE base system to image template ..." --progressbox 20 70

# we need emulator for second stage
cp /usr/bin/qemu-arm-static $DEST/cache/sdcard/usr/bin/

# and keys
d=$DEST/cache/sdcard/usr/share/keyrings/
test -d "$d" || mkdir -p "$d" && cp /usr/share/keyrings/debian-archive-keyring.gpg "$d" 

# enable arm binary format so that the cross-architecture chroot environment will work
test -e /proc/sys/fs/binfmt_misc/qemu-arm || update-binfmts --enable qemu-arm

# debootstrap second stage
chroot $DEST/cache/sdcard /bin/bash -c "/debootstrap/debootstrap --second-stage" | dialog --backtitle "$backtitle" --title "Installing $DISTRIBUTION $RELEASE base system to image template ..." --progressbox 20 70

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

# display welcome message at first root login
touch $DEST/cache/sdcard/root/.not_logged_in_yet

# update and upgrade
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y update" | dialog --progressbox "Updating package databases ..." 20 70

# install aditional packages
PAKETKI="alsa-utils automake btrfs-tools bash-completion bc bridge-utils bluez build-essential cmake cpufrequtils curl psmisc \
device-tree-compiler dosfstools evtest figlet fbset fping git haveged hddtemp hdparm hostapd htop i2c-tools ifenslave-2.6 \
iperf ir-keytable iotop iozone3 iw less libbluetooth-dev libbluetooth3 libtool libwrap0-dev libfuse2 libssl-dev lirc lsof makedev \
module-init-tools mtp-tools nano ntfs-3g ntp parted pkg-config pciutils pv python-smbus rfkill rsync screen stress sudo subversion \
sysfsutils toilet u-boot-tools unattended-upgrades unzip usbutils vlan wireless-tools weather-util weather-util-data wget \
wpasupplicant iptables dvb-apps libdigest-sha-perl libproc-processtable-perl w-scan apt-transport-https sysbench libusb-dev dialog fake-hwclock"

# additional distributios-specific packages
case $RELEASE in
	wheezy)
	PAKETKI="$PAKETKI libnl-dev"
	;;
	jessie)
	PAKETKI="$PAKETKI thin-provisioning-tools libnl-3-dev libnl-genl-3-dev libpam-systemd software-properties-common python-software-properties libnss-myhostname"
	;;
	trusty)
	PAKETKI="$PAKETKI libnl-3-dev libnl-genl-3-dev software-properties-common python-software-properties"
	;;
esac

# additional desktop packages
if [[ $BUILD_DESKTOP == yes ]]; then
	# common packages
	PAKETKI="$PAKETKI xserver-xorg xserver-xorg-core xfonts-base xinit nodm x11-xserver-utils xfce4 lxtask xterm mirage radiotray wicd thunar-volman galculator \
	gtk2-engines gtk2-engines-murrine gtk2-engines-pixbuf libgtk2.0-bin gcj-jre-headless xfce4-screenshooter libgnome2-perl"
	# release specific desktop packages
	case $RELEASE in
		wheezy)
		PAKETKI="$PAKETKI mozo pluma iceweasel icedove"
		;;
		jessie)
		PAKETKI="$PAKETKI mozo pluma iceweasel libreoffice-writer libreoffice-java-common icedove mpv"
		;;
		trusty)
		PAKETKI="$PAKETKI libreoffice-writer libreoffice-java-common thunderbird firefox gnome-icon-theme-full tango-icon-theme gvfs-backends"
		;;
	esac
	# hardware acceleration support packages
	# cache is not LINUXCONFIG and BRANCH specific, so installing anyway
	#if [[ $LINUXCONFIG == *sun* && $BRANCH != "next" ]] &&
	PAKETKI="$PAKETKI xorg-dev xutils-dev x11proto-dri2-dev xutils-dev libdrm-dev libvdpau-dev"
fi

# generate locales and install packets
display_alert "Install locales" "$DEST_LANG" "info"
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y -qq install locales"
if [ -f $DEST/cache/sdcard/etc/locale.gen ]; then sed -i "s/^# $DEST_LANG/$DEST_LANG/" $DEST/cache/sdcard/etc/locale.gen; fi
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/cache/sdcard /bin/bash -c "locale-gen $DEST_LANG"
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/cache/sdcard /bin/bash -c "export CHARMAP=$CONSOLE_CHAR FONTFACE=8x16 LANG=$DEST_LANG LANGUAGE=$DEST_LANG DEBIAN_FRONTEND=noninteractive"
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/cache/sdcard /bin/bash -c "update-locale LANG=$DEST_LANG LANGUAGE=$DEST_LANG LC_MESSAGES=POSIX"


install_packet "$PAKETKI" "Installing Armbian on the top of $DISTRIBUTION $RELEASE base system ..."

install_packet "console-setup console-data kbd console-common unicode-data" "Installing console packages"

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

display_alert "Closing debootstrap process and preparing cache." "" "info"
tar cp --directory=$DEST/cache/sdcard/ --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./tmp/*' \
--exclude='./mnt/*' --exclude='./sys/*' . | pv -p -b -r -s $(du -sb $DEST/cache/sdcard/ | cut -f1) -N "$cache_fname" | pigz > $cache_fname
fi
#
# mount proc, sys and dev
mount -t proc chproc $DEST/cache/sdcard/proc
mount -t sysfs chsys $DEST/cache/sdcard/sys
mount -t devtmpfs chdev $DEST/cache/sdcard/dev || mount --bind /dev $DEST/cache/sdcard/dev
mount -t devpts chpts $DEST/cache/sdcard/dev/pts
}