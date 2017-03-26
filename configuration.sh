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

# common options
REVISION="5.27$SUBREVISION" # all boards have same revision
ROOTPWD="1234" # Must be changed @first login
MAINTAINER="Igor Pecovnik" # deb signature
MAINTAINERMAIL="igor.pecovnik@****l.com" # deb signature
TZDATA=`cat /etc/timezone` # Timezone for target is taken from host or defined here.
USEALLCORES=yes # Use all CPU cores for compiling
EXIT_PATCHING_ERROR="" # exit patching if failed
HOST="$BOARD" # set hostname to the board
CACHEDIR=$DEST/cache
ROOTFSCACHE_VERSION=3

[[ -z $ROOTFS_TYPE ]] && ROOTFS_TYPE=ext4 # default rootfs type is ext4
[[ "ext4 f2fs btrfs nfs fel" != *$ROOTFS_TYPE* ]] && exit_with_error "Unknown rootfs type" "$ROOTFS_TYPE"

# Fixed image size is in 1M dd blocks (MiB)
# to get size of block device /dev/sdX execute as root:
# echo $(( $(blockdev --getsize64 /dev/sdX) / 1024 / 1024 ))
[[ "btrfs f2fs" == *$ROOTFS_TYPE* && -z $FIXED_IMAGE_SIZE ]] && exit_with_error "Please define FIXED_IMAGE_SIZE"

# small SD card with kernel, boot script and .dtb/.bin files
[[ $ROOTFS_TYPE == nfs ]] && FIXED_IMAGE_SIZE=64

# used by multiple sources - reduce code duplication
if [[ $USE_MAINLINE_GOOGLE_MIRROR == yes ]]; then
	MAINLINE_KERNEL_SOURCE='https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux-stable'
else
	MAINLINE_KERNEL_SOURCE='git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git'
fi
# allow upgrades for same major.minor versions
ARMBIAN_MAINLINE_KERNEL_VERSION='4.10'
MAINLINE_KERNEL_BRANCH=tag:v$(wget -qO- https://www.kernel.org/finger_banner | awk '{print $NF}' | grep -oE "^${ARMBIAN_MAINLINE_KERNEL_VERSION//./\\.}\.?[[:digit:]]*" | tail -1)
MAINLINE_KERNEL_DIR='linux-vanilla'

if [[ $USE_GITHUB_UBOOT_MIRROR == yes ]]; then
	MAINLINE_UBOOT_SOURCE='https://github.com/RobertCNelson/u-boot'
else
	MAINLINE_UBOOT_SOURCE='git://git.denx.de/u-boot.git'
fi
MAINLINE_UBOOT_BRANCH='tag:v2017.03'
MAINLINE_UBOOT_DIR='u-boot'

# Let's set default data if not defined in board configuration above
[[ -z $OFFSET ]] && OFFSET=1 # Bootloader space in MB (1 x 2048 = default)
ARCH=armhf
KERNEL_IMAGE_TYPE=zImage
SERIALCON=ttyS0

# WARNING: This option is deprecated
BOOTSIZE=0

# set unique mounting directory
SDCARD="sdcard-${BRANCH}-${BOARD}-${RELEASE}-${BUILD_DESKTOP}"
MOUNT="mount-${BRANCH}-${BOARD}-${RELEASE}-${BUILD_DESKTOP}"
DESTIMG="image-${BRANCH}-${BOARD}-${RELEASE}-${BUILD_DESKTOP}"

[[ ! -f $SRC/lib/config/sources/$LINUXFAMILY.conf ]] && \
	exit_with_error "Sources configuration not found" "$LINUXFAMILY"

source $SRC/lib/config/sources/$LINUXFAMILY.conf

if [[ -f $SRC/userpatches/sources/$LINUXFAMILY.conf ]]; then
	display_alert "Adding user provided $LINUXFAMILY overrides"
	source $SRC/userpatches/sources/$LINUXFAMILY.conf
fi

case $ARCH in
	arm64)
	[[ -z $KERNEL_COMPILER ]] && KERNEL_COMPILER="aarch64-linux-gnu-"
	[[ -z $UBOOT_COMPILER ]] && UBOOT_COMPILER="aarch64-linux-gnu-"
	[[ -z $INITRD_ARCH ]] && INITRD_ARCH=arm64
	QEMU_BINARY="qemu-aarch64-static"
	ARCHITECTURE=arm64
	;;

	armhf)
	[[ -z $KERNEL_COMPILER ]] && KERNEL_COMPILER="arm-linux-gnueabihf-"
	[[ -z $UBOOT_COMPILER ]] && UBOOT_COMPILER="arm-linux-gnueabihf-"
	[[ -z $INITRD_ARCH ]] && INITRD_ARCH=arm
	QEMU_BINARY="qemu-arm-static"
	ARCHITECTURE=arm
	;;
esac

# Here we want to use linux-sunxi-next and linux-sunxi-dev configs for sun*i
# except for sun8i-dev which is separate from sunxi-dev
[[ $LINUXFAMILY == sun*i && $BRANCH != default && ! ( $LINUXFAMILY == sun8i && $BRANCH == dev ) ]] && \
	LINUXCONFIG="linux-sunxi-${BRANCH}"

[[ -z $LINUXCONFIG ]] && LINUXCONFIG="linux-${LINUXFAMILY}-${BRANCH}"

if [[ $RELEASE == xenial ]]; then DISTRIBUTION="Ubuntu"; else DISTRIBUTION="Debian"; fi

# temporary hacks/overrides
case $LINUXFAMILY in
	sun*i)
	# 2016.07+ compilation fails due to GCC bug
	# works on Linaro 5.3.1, fails on Ubuntu 5.3.1
	UBOOT_NEEDS_GCC='< 5.3'
	;;

	# also affects XU4 next branch
	odroidxu4)
	[[ $BRANCH == next ]] && UBOOT_NEEDS_GCC='< 5.3'
	;;
esac

# Essential packages
PACKAGE_LIST="bc bridge-utils build-essential cpufrequtils device-tree-compiler figlet fbset fping \
	iw fake-hwclock wpasupplicant psmisc ntp parted rsync sudo curl linux-base dialog crda \
	wireless-regdb ncurses-term python3-apt sysfsutils toilet u-boot-tools unattended-upgrades \
	usbutils wireless-tools console-setup console-common unicode-data openssh-server initramfs-tools \
	ca-certificates"

# development related packages. remove when they are not needed for building packages in chroot
PACKAGE_LIST="$PACKAGE_LIST automake libwrap0-dev libssl-dev libusb-dev libusb-1.0-0-dev libnl-3-dev libnl-genl-3-dev"

# Non-essential packages
PACKAGE_LIST_ADDITIONAL="alsa-utils btrfs-tools dosfstools hddtemp iotop iozone3 stress sysbench screen ntfs-3g vim pciutils \
	evtest htop pv lsof apt-transport-https libfuse2 libdigest-sha-perl libproc-processtable-perl aptitude dnsutils f3 haveged \
	hdparm rfkill vlan sysstat bluez bluez-tools bash-completion hostapd git ethtool network-manager unzip ifenslave lirc \
	libpam-systemd iperf3 software-properties-common libnss-myhostname f2fs-tools"

PACKAGE_LIST_DESKTOP="xserver-xorg xserver-xorg-video-fbdev gvfs-backends gvfs-fuse xfonts-base xinit nodm x11-xserver-utils xfce4 lxtask xterm mirage thunar-volman galculator \
	gtk2-engines gtk2-engines-murrine gtk2-engines-pixbuf libgtk2.0-bin gcj-jre-headless xfce4-screenshooter libgnome2-perl gksu bluetooth \
	network-manager-gnome xfce4-notifyd gnome-keyring gcr libgck-1-0 libgcr-3-common p11-kit pasystray pavucontrol pulseaudio \
	paman pavumeter pulseaudio-module-gconf pulseaudio-module-bluetooth blueman libpam-gnome-keyring libgl1-mesa-dri mpv \
	libreoffice-writer libreoffice-style-tango libreoffice-gtk policykit-1 fbi"

# Release specific packages
case $RELEASE in
	jessie)
	PACKAGE_LIST_RELEASE="less kbd"
	PACKAGE_LIST_DESKTOP="$PACKAGE_LIST_DESKTOP mozo pluma iceweasel policykit-1-gnome eject"
	;;
	xenial)
	PACKAGE_LIST_RELEASE="man-db wget nano linux-firmware"
	PACKAGE_LIST_DESKTOP="$PACKAGE_LIST_DESKTOP thunderbird firefox gnome-icon-theme-full tango-icon-theme language-selector-gnome paprefs numix-gtk-theme"
	[[ $ARCH == armhf ]] && PACKAGE_LIST_DESKTOP="$PACKAGE_LIST_DESKTOP mate-utils ubuntu-mate-welcome mate-settings-daemon"
	;;
	stretch)
	PACKAGE_LIST_RELEASE="man-db less kbd"
	;;
esac

DEBIAN_MIRROR='httpredir.debian.org/debian'
UBUNTU_MIRROR='ports.ubuntu.com/'

# For user override
if [[ -f $SRC/userpatches/lib.config ]]; then
	display_alert "Using user configuration override" "userpatches/lib.config" "info"
	source $SRC/userpatches/lib.config
fi

# apt-cacher-ng mirror configurarion
if [[ $DISTRIBUTION == Ubuntu ]]; then
	APT_MIRROR=$UBUNTU_MIRROR
else
	APT_MIRROR=$DEBIAN_MIRROR
fi

[[ -n $APT_PROXY_ADDR ]] && display_alert "Using custom apt-cacher-ng address" "$APT_PROXY_ADDR" "info"

# Build final package list after possible override
PACKAGE_LIST="$PACKAGE_LIST $PACKAGE_LIST_RELEASE $PACKAGE_LIST_ADDITIONAL"
if [[ $ARCH == arm64 ]]; then
	PACKAGE_LIST_DESKTOP="${PACKAGE_LIST_DESKTOP/iceweasel/iceweasel:armhf}"
	PACKAGE_LIST_DESKTOP="${PACKAGE_LIST_DESKTOP/firefox/firefox:armhf}"
fi
[[ $BUILD_DESKTOP == yes ]] && PACKAGE_LIST="$PACKAGE_LIST $PACKAGE_LIST_DESKTOP"

# debug
cat <<-EOF >> $DEST/debug/output.log
## BUILD SCRIPT ENVIRONMENT

Version: $(cd $SRC/lib; git rev-parse @)

## BUILD CONFIGURATION

Build target:
Board: $BOARD
Branch: $BRANCH

Kernel configuration:
Repository: $KERNELSOURCE
Branch: $KERNELBRANCH
Config file: $LINUXCONFIG

U-boot configuration:
Repository: $BOOTSOURCE
Branch: $BOOTBRANCH
Offset: $OFFSET
Size: $BOOTSIZE

CPU configuration:
$CPUMIN - $CPUMAX with $GOVERNOR
EOF
