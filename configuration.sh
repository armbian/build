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

REVISION="5.12$SUBREVISON" # all boards have same revision
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
	MAINLINE_KERNEL='https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux-stable'
else
	MAINLINE_KERNEL='git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git'
fi
MAINLINE_KERNEL_BRANCH="v$(wget -qO-  https://www.kernel.org/finger_banner | grep "The latest st" | awk '{print $NF}' | head -1)"
MAINLINE_KERNEL_SOURCE="linux-vanilla"

MAINLINE_UBOOT='git://git.denx.de/u-boot.git'
MAINLINE_UBOOT_BRANCH="v$(git ls-remote git://git.denx.de/u-boot.git | grep -v rc | grep -v '\^' | tail -1 | cut -d'v' -f 2)"
MAINLINE_UBOOT_SOURCE='u-boot'

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
	QEMU_BINARY="qemu-aarch64-static"
	;;

	armhf)
	KERNEL_COMPILER="arm-linux-gnueabihf-"
	UBOOT_COMPILER="arm-linux-gnueabihf-"
	ARCHITECTURE=arm
	QEMU_BINARY="qemu-arm-static"
	;;
esac

# temporary hacks/overrides
case $LINUXFAMILY in
	pine64)
	# fix for u-boot needing armhf GCC 4.8
	UBOOT_COMPILER="arm-linux-gnueabihf-"
	;;
	marvell)
	# fix for u-boot needing arm soft float
	UBOOT_COMPILER="arm-linux-gnueabi-"
	;;
esac

# Essential packages
PACKAGE_LIST="automake bash-completion bc bridge-utils build-essential cmake cpufrequtils \
	device-tree-compiler dosfstools figlet fbset fping git haveged hdparm hostapd ifenslave-2.6 \
	iw libtool libwrap0-dev libssl-dev lirc lsof fake-hwclock wpasupplicant libusb-dev libusb-1.0-0-dev psmisc \
	ntp parted pkg-config pv rfkill rsync sudo curl dialog crda wireless-regdb ncurses-term \
	sysfsutils toilet u-boot-tools unattended-upgrades unzip usbutils vlan wireless-tools libnl-3-dev \
	console-setup console-data console-common unicode-data openssh-server libmtp-runtime initramfs-tools ca-certificates"

# Non-essential packages
PACKAGE_LIST_ADDITIONAL="alsa-utils btrfs-tools bluez hddtemp i2c-tools iperf ir-keytable iotop iozone3 weather-util weather-util-data stress \
	dvb-apps sysbench libbluetooth-dev libbluetooth3 subversion screen ntfs-3g vim pciutils evtest htop mtp-tools python-smbus \
	apt-transport-https libfuse2 libdigest-sha-perl libproc-processtable-perl w-scan aptitude dnsutils f3"

PACKAGE_LIST_DESKTOP="xserver-xorg xserver-xorg-core xfonts-base xinit nodm x11-xserver-utils xfce4 lxtask xterm mirage radiotray wicd thunar-volman galculator \
gtk2-engines gtk2-engines-murrine gtk2-engines-pixbuf libgtk2.0-bin gcj-jre-headless xfce4-screenshooter libgnome2-perl gksu wifi-radar"
# hardware acceleration support packages
if [[ $LINUXCONFIG == *sun* && $BRANCH == default ]]; then
	PACKAGE_LIST_DESKTOP="$PACKAGE_LIST_DESKTOP xorg-dev xutils-dev x11proto-dri2-dev xutils-dev libdrm-dev libvdpau-dev"
fi

# Release specific packages
case $RELEASE in
	wheezy)
	PACKAGE_LIST_RELEASE="less makedev kbd acpid acpi-support-base libnl-genl-3-dev"
	PACKAGE_LIST_DESKTOP="$PACKAGE_LIST_DESKTOP mozo pluma iceweasel icedove"
	PACKAGE_LIST_EXCLUDE=""
	;;
	jessie)
	PACKAGE_LIST_RELEASE="less makedev kbd thin-provisioning-tools libnl-genl-3-dev libpam-systemd \
		software-properties-common python-software-properties libnss-myhostname f2fs-tools libnl-genl-3-dev"
	PACKAGE_LIST_DESKTOP="$PACKAGE_LIST_DESKTOP mozo pluma iceweasel libreoffice-writer libreoffice-java-common icedove gvfs policykit-1 policykit-1-gnome eject"
	PACKAGE_LIST_EXCLUDE=""
	;;
	trusty)	
	PACKAGE_LIST_RELEASE="man-db wget iptables nano libnl-genl-3-dev software-properties-common \
		python-software-properties f2fs-tools acpid"
	PACKAGE_LIST_DESKTOP="$PACKAGE_LIST_DESKTOP libreoffice-writer libreoffice-java-common thunderbird firefox gnome-icon-theme-full tango-icon-theme gvfs-backends"
	PACKAGE_LIST_EXCLUDE="ureadahead plymouth"
	;;
	xenial)
	PACKAGE_LIST_RELEASE="man-db wget iptables nano thin-provisioning-tools libnl-genl-3-dev libpam-systemd \
		software-properties-common libnss-myhostname f2fs-tools"
	PACKAGE_LIST_DESKTOP="$PACKAGE_LIST_DESKTOP libreoffice-writer thunderbird firefox gnome-icon-theme-full tango-icon-theme gvfs-backends \
			policykit-1 xserver-xorg-video-fbdev"
	PACKAGE_LIST_EXCLUDE=""
	;;
esac

# Remove ARM64 missing packages. Temporally
PACKAGE_LIST_RELEASE=${PACKAGE_LIST_RELEASE//thin-provisioning-tools }

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
echo -e "Config: $LINUXCONFIG\nKernel source: $LINUXKERNEL\nBranch: $KERNELBRANCH" >> $DEST/debug/install.log
echo -e "linuxsource: $LINUXSOURCE\nOffset: $OFFSET\nbootsize: $BOOTSIZE" >> $DEST/debug/install.log
echo -e "bootloader: $BOOTLOADER\nbootsource: $BOOTSOURCE\nbootbranch: $BOOTBRANCH" >> $DEST/debug/install.log
echo -e "CPU $CPUMIN / $CPUMAX with $GOVERNOR" >> $DEST/debug/install.log

