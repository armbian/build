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
REVISION="5.21$SUBREVISION" # all boards have same revision
ROOTPWD="1234" # Must be changed @first login
MAINTAINER="Igor Pecovnik" # deb signature
MAINTAINERMAIL="igor.pecovnik@****l.com" # deb signature
TZDATA=`cat /etc/timezone` # Timezone for target is taken from host or defined here.
USEALLCORES=yes # Use all CPU cores for compiling
EXIT_PATCHING_ERROR="" # exit patching if failed
HOST="$BOARD" # set hostname to the board
CACHEDIR=$DEST/cache
[[ -z $ROOTFS_TYPE ]] && ROOTFS_TYPE=ext4 # default rootfs type is ext4

# used by multiple sources - reduce code duplication
if [[ $USE_MAINLINE_GOOGLE_MIRROR == yes ]]; then
	MAINLINE_KERNEL_SOURCE='https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux-stable'
else
	MAINLINE_KERNEL_SOURCE='git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git'
fi
# allow upgrades for same major.minor versions
ARMBIAN_MAINLINE_KERNEL_VERSION='4.7'
MAINLINE_KERNEL_BRANCH=tag:v$(wget -qO- https://www.kernel.org/finger_banner | awk '{print $NF}' | grep -oE "^${ARMBIAN_MAINLINE_KERNEL_VERSION//./\\.}\.?[[:digit:]]*")
MAINLINE_KERNEL_DIR='linux-vanilla'

MAINLINE_UBOOT_SOURCE='git://git.denx.de/u-boot.git'
#MAINLINE_UBOOT_BRANCH="v$(git ls-remote git://git.denx.de/u-boot.git | grep -v rc | grep -v '\^' | tail -1 | cut -d'v' -f 2)"
MAINLINE_UBOOT_BRANCH='tag:v2016.09'
MAINLINE_UBOOT_DIR='u-boot'

# Let's set default data if not defined in board configuration above

OFFSET=1 # Bootloader space in MB (1 x 2048 = default)
ARCH=armhf
KERNEL_IMAGE_TYPE=zImage
SERIALCON=ttyS0
BOOTSIZE=0 # Mb size of boot partition

if [[ -f $SRC/lib/config/sources/$LINUXFAMILY.conf ]]; then
	source $SRC/lib/config/sources/$LINUXFAMILY.conf
else
	exit_with_error "Sources configuration not found" "$LINUXFAMILY"
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

[[ $LINUXFAMILY == sun*i && $BRANCH != default && $LINUXFAMILY != sun8i ]] && LINUXCONFIG="linux-sunxi-${BRANCH}"
[[ $LINUXFAMILY == udoo && $BRANCH == default ]] && LINUXCONFIG="linux-$BOARD-default"
[[ -z $LINUXCONFIG ]] && LINUXCONFIG="linux-${LINUXFAMILY}-${BRANCH}"

# naming to distro
if [[ $RELEASE == trusty || $RELEASE == xenial ]]; then DISTRIBUTION="Ubuntu"; else DISTRIBUTION="Debian"; fi

# temporary hacks/overrides
case $LINUXFAMILY in
	sun*i)
	# 2016.07 compilation fails due to GCC bug
	# works on Linaro 5.3.1, fails on Ubuntu 5.3.1
	UBOOT_NEEDS_GCC='< 5.3'
	;;
esac

# Essential packages
PACKAGE_LIST="bc bridge-utils build-essential cpufrequtils device-tree-compiler dosfstools figlet \
	fbset fping ifenslave-2.6 iw lirc fake-hwclock wpasupplicant psmisc ntp parted rsync sudo curl \
	dialog crda wireless-regdb ncurses-term python3-apt sysfsutils toilet u-boot-tools unattended-upgrades \
	unzip usbutils wireless-tools console-setup console-common unicode-data openssh-server initramfs-tools ca-certificates"

# development related packages. remove when they are not needed for building packages in chroot
PACKAGE_LIST="$PACKAGE_LIST automake libwrap0-dev libssl-dev libusb-dev libusb-1.0-0-dev libnl-3-dev libnl-genl-3-dev"

# Non-essential packages
PACKAGE_LIST_ADDITIONAL="alsa-utils btrfs-tools hddtemp iotop iozone3 stress sysbench screen ntfs-3g vim pciutils evtest htop pv lsof \
	apt-transport-https libfuse2 libdigest-sha-perl libproc-processtable-perl w-scan aptitude dnsutils f3 haveged hdparm rfkill \
	vlan sysstat bluez bluez-tools bash-completion hostapd git"

PACKAGE_LIST_DESKTOP="xserver-xorg xserver-xorg-video-fbdev gvfs-backends gvfs-fuse xfonts-base xinit nodm x11-xserver-utils xfce4 lxtask xterm mirage thunar-volman galculator \
	gtk2-engines gtk2-engines-murrine gtk2-engines-pixbuf libgtk2.0-bin gcj-jre-headless xfce4-screenshooter libgnome2-perl gksu bluetooth \
	network-manager network-manager-gnome xfce4-notifyd gnome-keyring gcr libgck-1-0 libgcr-3-common p11-kit pasystray pavucontrol pulseaudio \
	paman pavumeter pulseaudio-module-gconf pulseaudio-module-bluetooth blueman libpam-gnome-keyring libgl1-mesa-dri mpv"

PACKAGE_LIST_EXCLUDE="xfce4-mixer"

# Release specific packages
case $RELEASE in
	wheezy)
	PACKAGE_LIST_RELEASE="less makedev kbd acpid acpi-support-base iperf libudev1"
	;;
	jessie)
	PACKAGE_LIST_RELEASE="less makedev kbd libpam-systemd iperf3 software-properties-common libnss-myhostname f2fs-tools"
	PACKAGE_LIST_DESKTOP="$PACKAGE_LIST_DESKTOP mozo pluma iceweasel libreoffice-writer icedove policykit-1 policykit-1-gnome eject"
	;;
	trusty)
	PACKAGE_LIST_RELEASE="man-db wget nano software-properties-common iperf f2fs-tools acpid"
	PACKAGE_LIST_EXCLUDE="$PACKAGE_LIST_EXCLUDE ureadahead plymouth"
	;;
	xenial)
	PACKAGE_LIST_RELEASE="man-db wget nano libpam-systemd software-properties-common libnss-myhostname f2fs-tools iperf3 paprefs"
	PACKAGE_LIST_DESKTOP="$PACKAGE_LIST_DESKTOP libreoffice-writer thunderbird firefox gnome-icon-theme-full tango-icon-theme policykit-1"
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
