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

REVISION="5.17$SUBREVISION" # all boards have same revision
ROOTPWD="1234" # Must be changed @first login
MAINTAINER="Igor Pecovnik" # deb signature
MAINTAINERMAIL="igor.pecovnik@****l.com" # deb signature
SDSIZE="4000" # SD image size in MB
TZDATA=`cat /etc/timezone` # Timezone for target is taken from host or defined here.
USEALLCORES="yes" # Use all CPU cores for compiling
EXIT_PATCHING_ERROR="" # exit patching if failed
MISC1="https://github.com/linux-sunxi/sunxi-tools.git" # Allwinner fex compiler / decompiler
MISC1_DIR="sunxi-tools"	# local directory
MISC5="https://github.com/hglm/a10disp/" # Display changer for Allwinner
MISC5_DIR="sunxi-display-changer" # local directory
HOST="$BOARD" # set hostname to the board
CACHEDIR=$DEST/cache

# used by multiple sources - reduce code duplication
if [[ $USE_MAINLINE_GOOGLE_MIRROR == yes ]]; then
	MAINLINE_KERNEL_SOURCE='https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux-stable'
else
	MAINLINE_KERNEL_SOURCE='git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git'
fi
# allow upgrades for same major.minor versions
ARMBIAN_MAINLINE_KERNEL_VERSION="4.7"
MAINLINE_KERNEL_BRANCH=tag:v$(wget -qO- https://www.kernel.org/finger_banner | awk '{print $NF}' | grep -oE "^${ARMBIAN_MAINLINE_KERNEL_VERSION//./\\.}\.?[[:digit:]]*")
#MAINLINE_KERNEL_BRANCH="v$(wget -qO- https://www.kernel.org/finger_banner | grep "The latest st" | awk '{print $NF}' | head -1)"
MAINLINE_KERNEL_DIR="linux-vanilla"

MAINLINE_UBOOT_SOURCE='git://git.denx.de/u-boot.git'
#MAINLINE_UBOOT_BRANCH="v$(git ls-remote git://git.denx.de/u-boot.git | grep -v rc | grep -v '\^' | tail -1 | cut -d'v' -f 2)"
MAINLINE_UBOOT_BRANCH='tag:v2016.07'
MAINLINE_UBOOT_DIR='u-boot'

if [[ -f $SRC/lib/config/sources/$LINUXFAMILY.conf ]]; then
	source $SRC/lib/config/sources/$LINUXFAMILY.conf
else
	exit_with_error "Sources configuration not found" "$LINUXFAMILY"
fi

# Let's set defalt data if not defined in board configuration above

[[ -z $OFFSET ]] && OFFSET=1 # Bootloader space in MB (1 x 2048 = default)
[[ -z $ARCH ]] && ARCH=armhf
[[ -z $KERNEL_IMAGE_TYPE ]] && KERNEL_IMAGE_TYPE=zImage
[[ -z $SERIALCON ]] && SERIALCON=ttyS0
[[ -z $BOOTSIZE ]] && BOOTSIZE=0 # Mb size of boot partition

[[ $LINUXFAMILY == sun*i && $BRANCH != default && $LINUXFAMILY != sun8i ]] && LINUXCONFIG="linux-sunxi-${BRANCH}"
[[ -z $LINUXCONFIG ]] && LINUXCONFIG="linux-${LINUXFAMILY}-${BRANCH}"

# naming to distro
if [[ $RELEASE == trusty || $RELEASE == xenial ]]; then DISTRIBUTION="Ubuntu"; else DISTRIBUTION="Debian"; fi

case $ARCH in
	arm64)
	KERNEL_COMPILER="aarch64-linux-gnu-"
	UBOOT_COMPILER="aarch64-linux-gnu-"
	ARCHITECTURE=arm64
	INITRD_ARCH=arm64
	QEMU_BINARY="qemu-aarch64-static"
	;;

	armhf)
	KERNEL_COMPILER="arm-linux-gnueabihf-"
	UBOOT_COMPILER="arm-linux-gnueabihf-"
	ARCHITECTURE=arm
	INITRD_ARCH=arm
	QEMU_BINARY="qemu-arm-static"
	;;
esac

# temporary hacks/overrides
case $LINUXFAMILY in
	sun*i)
	# 2016.07 compilation fails due to GCC bug
	# works on Linaro 5.3.1, fails on Ubuntu 5.3.1
	UBOOT_NEEDS_GCC='< 5.3'
	;;
	pine64)
	# fix for initramfs update script in board support package
	[[ $BRANCH == default ]] && INITRD_ARCH=arm
	;;
	marvell)
	# fix for u-boot needing arm soft float compiler
	UBOOT_COMPILER="arm-linux-gnueabi-"
	;;
esac

# Essential packages
PACKAGE_LIST="bash-completion bc bridge-utils build-essential cpufrequtils device-tree-compiler dosfstools figlet \
	fbset fping git hostapd ifenslave-2.6 iw lirc fake-hwclock wpasupplicant psmisc ntp parted rsync sudo curl \
	dialog crda wireless-regdb ncurses-term python3-apt sysfsutils toilet u-boot-tools unattended-upgrades \
	unzip usbutils wireless-tools console-setup console-data console-common unicode-data openssh-server initramfs-tools ca-certificates"

# development related packages. remove when they are not needed for building packages in chroot
PACKAGE_LIST="$PACKAGE_LIST automake cmake libwrap0-dev libssl-dev libtool pkg-config libusb-dev libusb-1.0-0-dev libnl-3-dev libnl-genl-3-dev"

# Non-essential packages
PACKAGE_LIST_ADDITIONAL="alsa-utils btrfs-tools hddtemp iotop iozone3 stress sysbench screen ntfs-3g vim pciutils evtest htop pv lsof \
	apt-transport-https libfuse2 libdigest-sha-perl libproc-processtable-perl w-scan aptitude dnsutils f3 haveged hdparm rfkill \
	vlan sysstat"

PACKAGE_LIST_DESKTOP="xserver-xorg xserver-xorg-core xfonts-base xinit nodm x11-xserver-utils xfce4 lxtask xterm mirage radiotray wicd thunar-volman galculator \
	gtk2-engines gtk2-engines-murrine gtk2-engines-pixbuf libgtk2.0-bin gcj-jre-headless xfce4-screenshooter libgnome2-perl gksu wifi-radar bluetooth"

# hardware acceleration support packages. remove when they are not needed for building packages in chroot
if [[ $LINUXCONFIG == *sun* && $BRANCH == default ]]; then
	PACKAGE_LIST_DESKTOP="$PACKAGE_LIST_DESKTOP xorg-dev xutils-dev x11proto-dri2-dev xutils-dev libdrm-dev libvdpau-dev"
fi

PACKAGE_LIST_EXCLUDE=""

# Release specific packages
case $RELEASE in
	wheezy)
	PACKAGE_LIST_RELEASE="less makedev kbd acpid acpi-support-base iperf libudev1"
	PACKAGE_LIST_DESKTOP="$PACKAGE_LIST_DESKTOP mozo pluma iceweasel icedove"
	;;
	jessie)
	PACKAGE_LIST_RELEASE="less makedev kbd libpam-systemd iperf3 software-properties-common \
		libnss-myhostname f2fs-tools"
	PACKAGE_LIST_DESKTOP="$PACKAGE_LIST_DESKTOP mozo pluma iceweasel libreoffice-writer libreoffice-java-common icedove gvfs policykit-1 policykit-1-gnome eject"
	;;
	trusty)
	PACKAGE_LIST_RELEASE="man-db wget nano software-properties-common iperf f2fs-tools acpid"
	PACKAGE_LIST_DESKTOP="$PACKAGE_LIST_DESKTOP libreoffice-writer libreoffice-java-common thunderbird firefox gnome-icon-theme-full tango-icon-theme gvfs-backends"
	PACKAGE_LIST_EXCLUDE="ureadahead plymouth"
	;;
	xenial)
	PACKAGE_LIST_RELEASE="man-db wget nano libpam-systemd software-properties-common libnss-myhostname f2fs-tools iperf3"
	PACKAGE_LIST_DESKTOP="$PACKAGE_LIST_DESKTOP libreoffice-writer thunderbird firefox gnome-icon-theme-full tango-icon-theme gvfs-backends \
			policykit-1 xserver-xorg-video-fbdev"
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
## BUILD CONFIGURATION
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
