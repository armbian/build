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

REVISION="5.11" # all boards have same revision
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

# board family configurations
case $LINUXFAMILY in

	sun4i|sun5i|sun6i|sun7i|sun9i)
		[[ -z $LINUXCONFIG && $BRANCH == "default" ]] && LINUXCONFIG="linux-"$LINUXFAMILY-"$BRANCH"
		[[ -z $LINUXCONFIG && $BRANCH != "default" ]] && LINUXCONFIG="linux-sunxi-"$BRANCH
		# Kernel
		KERNEL_DEFAULT='https://github.com/linux-sunxi/linux-sunxi'
		KERNEL_DEFAULT_BRANCH="sunxi-3.4"
		KERNEL_DEFAULT_SOURCE="linux-sunxi"
		KERNEL_DEV='git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git'
		[ "$USE_MAINLINE_GOOGLE_MIRROR" = "yes" ] && KERNEL_DEV='https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux-stable'
		KERNEL_DEV_BRANCH=""
		KERNEL_DEV_SOURCE="linux-vanilla"
		KERNEL_NEXT='git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git'
		[ "$USE_MAINLINE_GOOGLE_MIRROR" = "yes" ] && KERNEL_NEXT='https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux-stable'
		KERNEL_NEXT_BRANCH="v"`wget -qO-  https://www.kernel.org/finger_banner | grep "The latest st" | awk '{print $NF}' | head -1`
		KERNEL_NEXT_SOURCE="linux-vanilla"
		# U-boot
		BOOTLOADER="git://git.denx.de/u-boot.git"
		BOOTSOURCE="u-boot"
		# latest stable v2016.03 broken gmac on sun7i, fixing it for DEFAULT and NEXT
		#UBOOT_DEFAULT_BRANCH="v"$(git ls-remote git://git.denx.de/u-boot.git | grep -v rc | grep -v "\^" | tail -1 | cut -d "v" -f 2)		
		UBOOT_DEFAULT_BRANCH="v2016.01"
		if [[ $BOARD == lime* || $BOARD == micro ]]; then UBOOT_DEFAULT_BRANCH="v2016.05-rc1"; fi 
		UBOOT_NEXT_BRANCH=$UBOOT_DEFAULT_BRANCH
		UBOOT_DEV_BRANCH=""
	;;

	sun8i)
		[[ -z $LINUXCONFIG ]] && LINUXCONFIG="linux-"$LINUXFAMILY-"$BRANCH"
		#KERNEL_DEFAULT="https://github.com/O-Computers/linux-sunxi"
		#KERNEL_DEFAULT_BRANCH="h3-wip"
		#KERNEL_DEFAULT_SOURCE="linux-sun8i"
		KERNEL_DEFAULT="https://github.com/igorpecovnik/linux"
		KERNEL_DEFAULT_BRANCH="sun8i"
		KERNEL_DEFAULT_SOURCE="linux-sun8i"
		KERNEL_DEV="https://github.com/wens/linux"
		KERNEL_DEV_BRANCH=h3-emac
		KERNEL_DEV_SOURCE="linux-sun8i-mainline"
		BOOTLOADER="git://git.denx.de/u-boot.git"
		BOOTSOURCE="u-boot"
		UBOOT_DEFAULT_BRANCH="v"$(git ls-remote git://git.denx.de/u-boot.git | grep -v rc | grep -v "\^" | tail -1 | cut -d "v" -f 2)
		UBOOT_DEV_BRANCH=""
	;;

	odroidxu4)
		KERNEL_DEFAULT='https://github.com/hardkernel/linux'
		KERNEL_DEFAULT_BRANCH="odroidxu3-3.10.y"
		KERNEL_DEFAULT_SOURCE="linux-odroidxu4"
		KERNEL_NEXT='https://github.com/tobetter/linux'
		KERNEL_NEXT_BRANCH="odroidxu4-v4.2"
		KERNEL_NEXT_SOURCE="linux-odroidxu-next"
		BOOTLOADER="https://github.com/hardkernel/u-boot.git"
		BOOTBRANCH="odroidxu3-v2012.07"
		BOOTSOURCE="u-boot-odroidxu"
	;;

	odroidc1)
		KERNEL_DEFAULT='https://github.com/hardkernel/linux'
		KERNEL_DEFAULT_BRANCH="odroidc-3.10.y"
		KERNEL_DEFAULT_SOURCE="linux-odroidc1"
		KERNEL_NEXT='https://github.com/tobetter/linux'
		KERNEL_NEXT_BRANCH="odroidxu4-v4.2"
		KERNEL_NEXT_SOURCE="linux-odroidxu-next"
		BOOTLOADER="https://github.com/hardkernel/u-boot.git"
		BOOTBRANCH="odroidc-v2011.03"
		BOOTSOURCE="u-boot-odroidc1"
		UBOOT_NEEDS_GCC="< 5.0"
	;;
	
	odroidc2)
		KERNEL_DEFAULT='https://github.com/hardkernel/linux'
		KERNEL_DEFAULT_BRANCH="odroidc2-3.14.y"
		KERNEL_DEFAULT_SOURCE="linux-odroidc2"
		BOOTLOADER="https://github.com/hardkernel/u-boot.git"
		BOOTBRANCH="odroidc2-v2015.01"
		BOOTSOURCE="u-boot-odroidc2"
	;;
	
	udoo)
		KERNEL_DEFAULT="https://github.com/UDOOboard/linux_kernel"
		KERNEL_DEFAULT_BRANCH="3.14-1.0.x-udoo"
		KERNEL_DEFAULT_SOURCE="linux-udoo"
		KERNEL_NEXT="https://github.com/patrykk/linux-udoo"
		KERNEL_NEXT_BRANCH="v4.4.0-6-vivante-5.0.11.p7.3"
		KERNEL_NEXT_SOURCE="linux-udoo-next"
		BOOTLOADER="https://github.com/UDOOboard/uboot-imx"
		BOOTBRANCH="2015.10.fslc-qdl"
		BOOTSOURCE="u-boot-udoo"
	;;

	neo)
		KERNEL_DEFAULT='https://github.com/UDOOboard/linux_kernel'
		#KERNEL_DEFAULT_BRANCH="imx_3.14.28_1.0.0_ga_neo"
		KERNEL_DEFAULT_BRANCH="3.14-1.0.x-udoo"
		#KERNEL_DEFAULT_SOURCE="linux-udoo-neo"
		KERNEL_DEFAULT_SOURCE="linux-udoo"
		BOOTLOADER="https://github.com/UDOOboard/uboot-imx"
		BOOTBRANCH="2015.04.imx-neo"
		BOOTSOURCE="u-boot-neo"
	;;

	cubox)
		KERNEL_DEFAULT='https://github.com/linux4kix/linux-linaro-stable-mx6'
		KERNEL_DEFAULT_BRANCH="linux-linaro-lsk-v3.14-mx6"
		KERNEL_DEFAULT_SOURCE="linux-cubox"
		KERNEL_NEXT='git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git'
		[ "$USE_MAINLINE_GOOGLE_MIRROR" = "yes" ] && KERNEL_NEXT='https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux-stable'
		KERNEL_NEXT_BRANCH="v"`wget -qO-  https://www.kernel.org/finger_banner | grep "The latest st" | awk '{print $NF}' | head -1`
		KERNEL_NEXT_SOURCE="linux-vanilla"
		KERNEL_DEV='https://github.com/SolidRun/linux-fslc'
		KERNEL_DEV_BRANCH="3.14-1.0.x-mx6-sr"
		KERNEL_DEV_SOURCE="linux-cubox"
		BOOTLOADER="https://github.com/SolidRun/u-boot-imx6"
		BOOTBRANCH="imx6"
		BOOTSOURCE="u-boot-cubox"
	;;

	s500)
		KERNEL_DEFAULT='https://github.com/LeMaker/linux-actions'
		KERNEL_DEFAULT_BRANCH="linux-3.10.y"
		KERNEL_DEFAULT_SOURCE="linux-s500"
		BOOTLOADER="https://github.com/LeMaker/u-boot-actions"
		BOOTBRANCH="s500-master"
		BOOTSOURCE="u-boot-s500"
	;;

	toradex)
		KERNEL_DEFAULT="git://git.toradex.com/linux-toradex.git"
		KERNEL_DEFAULT_BRANCH="toradex_imx_3.14.28_1.0.0_ga"
		KERNEL_DEFAULT_SOURCE="linux-toradex"
		BOOTLOADER="git://git.toradex.com/u-boot-toradex.git"
		BOOTBRANCH="2015.04-toradex"
		BOOTSOURCE="u-boot-toradex"
	;;

	marvell)
		KERNEL_DEFAULT="https://github.com/SolidRun/linux-armada38x"
		KERNEL_DEFAULT_BRANCH="linux-3.10.70-15t1-clearfog"
		KERNEL_DEFAULT_SOURCE="linux-armada"
		KERNEL_NEXT='git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git'
		[ "$USE_MAINLINE_GOOGLE_MIRROR" = "yes" ] && KERNEL_NEXT='https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux-stable'
		KERNEL_NEXT_BRANCH="v"`wget -qO-  https://www.kernel.org/finger_banner | grep "The latest st" | awk '{print $NF}' | head -1`
		KERNEL_NEXT_SOURCE="linux-vanilla"
		KERNEL_DEV='git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git'
		[ "$USE_MAINLINE_GOOGLE_MIRROR" = "yes" ] && KERNEL_DEV='https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux-stable'
		KERNEL_DEV_BRANCH=""
		KERNEL_DEV_SOURCE="linux-vanilla"
		BOOTLOADER="https://github.com/SolidRun/u-boot-armada38x"
		BOOTBRANCH="u-boot-2013.01-15t1-clearfog"
		BOOTSOURCE="u-boot-armada"
	;;

	*)
		if [[ -f $SRC/lib/config/sources/$LINUXFAMILY.family ]]; then
			source $SRC/lib/config/sources/$LINUXFAMILY.family
		else
			exit_with_error "Sources configuration not found" "$LINUXFAMILY"
		fi
	;;
esac

# Let's set defalt data if not defined in board configuration above

[[ -z $OFFSET ]] && OFFSET=1 # Bootloader space in MB (1 x 2048 = default)
[[ -z $ARCH ]] && ARCH=armhf
[[ -z $KERNEL_IMAGE_TYPE ]] && KERNEL_IMAGE_TYPE=zImage
[[ -z $SERIALCON ]] && SERIALCON=ttyS0
[[ -z $BOOTSIZE ]] && BOOTSIZE=0 # Mb size of boot partition

[[ -z $LINUXCONFIG ]] && LINUXCONFIG="linux-$LINUXFAMILY-$BRANCH"
[[ -z $LINUXKERNEL ]] && eval LINUXKERNEL=\$KERNEL_${BRANCH^^}
[[ -z $LINUXSOURCE ]] && eval LINUXSOURCE=\$KERNEL_${BRANCH^^}"_SOURCE"
[[ -z $KERNELBRANCH ]] && eval KERNELBRANCH=\$KERNEL_${BRANCH^^}"_BRANCH"
[[ -z $BOOTLOADER ]] && eval BOOTLOADER=\$UBOOT_${BRANCH^^}
[[ -z $BOOTSOURCE ]] && eval BOOTSOURCE=\$UBOOT_${BRANCH^^}"_SOURCE"
[[ -z $BOOTBRANCH ]] && eval BOOTBRANCH=\$UBOOT_${BRANCH^^}"_BRANCH"
[[ -z $CPUMIN && $LINUXFAMILY == sun*i ]] && CPUMIN="480000" && CPUMAX="1010000" && GOVERNOR="interactive"
[[ $BRANCH != "default" && $LINUXFAMILY == sun*i ]] && GOVERNOR="ondemand"
[[ -z $CPUMIN && $LINUXFAMILY == odroidxu4 ]] && CPUMIN="600000" && CPUMAX="2000000" && GOVERNOR="conservative"
[[ -z $CPUMIN && $LINUXFAMILY == odroidc1 ]] && CPUMIN="504000" && CPUMAX="1728000" && GOVERNOR="interactive"
[[ -z $CPUMIN && $LINUXFAMILY == cubox ]] && CPUMIN="396000" && CPUMAX="996000" && GOVERNOR="interactive"
[[ -z $CPUMIN && $LINUXFAMILY == s500 ]] && CPUMIN="408000" && CPUMAX="1104000" && GOVERNOR="interactive"
[[ -z $CPUMIN && $LINUXFAMILY == marvell ]] && CPUMIN="800000" && CPUMAX="1600000" && GOVERNOR="ondemand"
[[ -z $CPUMIN && ($LINUXFAMILY == udoo || $LINUXFAMILY == neo ) ]] && CPUMIN="392000" && CPUMAX="996000" && GOVERNOR="interactive"
[[ -z $GOVERNOR ]] && GOVERNOR="ondemand"

# naming to distro
if [[ $RELEASE == trusty || $RELEASE == xenial ]]; then DISTRIBUTION="Ubuntu"; else DISTRIBUTION="Debian"; fi

case $ARCH in
	arm64)
	CROSS_COMPILE="$CCACHE aarch64-linux-gnu-"
	COMPILER="aarch64-linux-gnu-"
	ARCHITECTURE=arm64
	QEMU_BINARY="qemu-aarch64-static"
	;;

	armhf)
	CROSS_COMPILE="$CCACHE arm-linux-gnueabihf-"
	COMPILER="arm-linux-gnueabihf-"
	ARCHITECTURE=arm
	QEMU_BINARY="qemu-arm-static"
	;;
esac

# Essential packages
PACKAGE_LIST="automake bash-completion bc bridge-utils build-essential cmake cpufrequtils \
	device-tree-compiler dosfstools figlet fbset fping git haveged hdparm hostapd ifenslave-2.6 \
	iw libtool libwrap0-dev libssl-dev lirc lsof fake-hwclock wpasupplicant libusb-dev psmisc \
	ntp parted pkg-config pv rfkill rsync sudo curl dialog crda wireless-regdb ncurses-term \
	sysfsutils toilet u-boot-tools unattended-upgrades unzip usbutils vlan wireless-tools \
	console-setup console-data console-common unicode-data openssh-server libmtp-runtime initramfs-tools ca-certificates"

# Non-essential packages
PACKAGE_LIST_ADDITIONAL="alsa-utils btrfs-tools bluez hddtemp i2c-tools iperf ir-keytable iotop iozone3 weather-util weather-util-data stress \
	dvb-apps sysbench libbluetooth-dev libbluetooth3 subversion screen ntfs-3g vim pciutils evtest htop mtp-tools python-smbus \
	apt-transport-https libfuse2 libdigest-sha-perl libproc-processtable-perl w-scan aptitude dnsutils f3"

# Release specific packages
case $RELEASE in
	wheezy)
	PACKAGE_LIST_RELEASE="less makedev kbd libnl-3-dev acpid acpi-support-base libnl-genl-3-dev"
	PACKAGE_LIST_EXCLUDE=""
	;;
	jessie)
	PACKAGE_LIST_RELEASE="less makedev kbd thin-provisioning-tools libnl-3-dev libnl-genl-3-dev libpam-systemd \
		software-properties-common python-software-properties libnss-myhostname f2fs-tools libnl-genl-3-dev"
	PACKAGE_LIST_EXCLUDE=""
	;;
	trusty)	
	PACKAGE_LIST_RELEASE="man-db wget iptables nano libnl-3-dev libnl-genl-3-dev software-properties-common \
		python-software-properties f2fs-tools acpid"
	PACKAGE_LIST_EXCLUDE="ureadahead plymouth"
	;;
	xenial)
	PACKAGE_LIST_RELEASE="man-db wget iptables nano thin-provisioning-tools libnl-3-dev libnl-genl-3-dev libpam-systemd \
		software-properties-common python-software-properties libnss-myhostname f2fs-tools"
	PACKAGE_LIST_EXCLUDE=""
	;;
esac

# Remove ARM64 missing packages. Temporally
PACKAGE_LIST_RELEASE=${PACKAGE_LIST_RELEASE//thin-provisioning-tools }

# additional desktop packages
if [[ $BUILD_DESKTOP == yes ]]; then
	# common packages
	PACKAGE_LIST_DESKTOP="xserver-xorg xserver-xorg-core xfonts-base xinit nodm x11-xserver-utils xfce4 lxtask xterm mirage radiotray wicd thunar-volman galculator \
	gtk2-engines gtk2-engines-murrine gtk2-engines-pixbuf libgtk2.0-bin gcj-jre-headless xfce4-screenshooter libgnome2-perl gksu wifi-radar"
	# release specific desktop packages
	case $RELEASE in
		wheezy)
		PACKAGE_LIST_DESKTOP="$PACKAGE_LIST_DESKTOP mozo pluma iceweasel icedove"
		;;
		jessie)
		PACKAGE_LIST_DESKTOP="$PACKAGE_LIST_DESKTOP mozo pluma iceweasel libreoffice-writer libreoffice-java-common icedove gvfs policykit-1 policykit-1-gnome eject"
		;;
		trusty)
		PACKAGE_LIST_DESKTOP="$PACKAGE_LIST_DESKTOP libreoffice-writer libreoffice-java-common thunderbird firefox gnome-icon-theme-full tango-icon-theme gvfs-backends"
		;;
		xenial)
		PACKAGE_LIST_DESKTOP="$PACKAGE_LIST_DESKTOP libreoffice-writer thunderbird firefox gnome-icon-theme-full tango-icon-theme gvfs-backends \
			policykit-1 xserver-xorg-video-fbdev"
		;;
	esac
	# hardware acceleration support packages
	if [[ $LINUXCONFIG == *sun* && $BRANCH == default ]]; then
		PACKAGE_LIST_DESKTOP="$PACKAGE_LIST_DESKTOP xorg-dev xutils-dev x11proto-dri2-dev xutils-dev libdrm-dev libvdpau-dev"
	fi
else
	PACKAGE_LIST_DESKTOP=""
fi

# For user override
if [[ -f "$SRC/userpatches/lib.config" ]]; then
	display_alert "Using user configuration override" "userpatches/lib.config" "info"
	source $SRC/userpatches/lib.config
fi

# Build final package list after possible override
PACKAGE_LIST="$PACKAGE_LIST $PACKAGE_LIST_RELEASE $PACKAGE_LIST_ADDITIONAL $PACKAGE_LIST_DESKTOP"

# debug
echo -e "Config: $LINUXCONFIG\nKernel source: $LINUXKERNEL\nBranch: $KERNELBRANCH" >> $DEST/debug/install.log
echo -e "linuxsource: $LINUXSOURCE\nOffset: $OFFSET\nbootsize: $BOOTSIZE" >> $DEST/debug/install.log
echo -e "bootloader: $BOOTLOADER\nbootsource: $BOOTSOURCE\nbootbranch: $BOOTBRANCH" >> $DEST/debug/install.log
echo -e "CPU $CPUMIN / $CPUMAX with $GOVERNOR" >> $DEST/debug/install.log

