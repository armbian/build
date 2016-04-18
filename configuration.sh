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

REVISION="5.07" # all boards have same revision
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
		UBOOT_DEFAULT="git://git.denx.de/u-boot.git"
		# latest stable v2016.03 broken gmac on sun7i, fixing it for DEFAULT and NEXT
		#UBOOT_DEFAULT_BRANCH="v"$(git ls-remote git://git.denx.de/u-boot.git | grep -v rc | grep -v "\^" | tail -1 | cut -d "v" -f 2)
		UBOOT_DEFAULT_BRANCH="v2016.01"
		UBOOT_DEFAULT_SOURCE="u-boot"
		UBOOT_NEXT=$UBOOT_DEFAULT
		UBOOT_NEXT_BRANCH=$UBOOT_DEFAULT_BRANCH
		UBOOT_NEXT_SOURCE=$UBOOT_DEFAULT_SOURCE
		UBOOT_DEV=$UBOOT_DEFAULT
		UBOOT_DEV_BRANCH=""
		UBOOT_DEV_SOURCE=$UBOOT_DEFAULT_SOURCE
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

		UBOOT_DEFAULT="git://git.denx.de/u-boot.git"
		UBOOT_DEFAULT_BRANCH="v"$(git ls-remote git://git.denx.de/u-boot.git | grep -v rc | grep -v "\^" | tail -1 | cut -d "v" -f 2)
		UBOOT_DEFAULT_SOURCE="u-boot"
		UBOOT_DEV=$UBOOT_DEFAULT
		UBOOT_DEV_BRANCH=""
		UBOOT_DEV_SOURCE=$UBOOT_DEFAULT_SOURCE
	;;

	odroidxu4)
		KERNEL_DEFAULT='https://github.com/hardkernel/linux'
		KERNEL_DEFAULT_BRANCH="odroidxu3-3.10.y"
		KERNEL_DEFAULT_SOURCE="linux-odroidxu4"
		KERNEL_NEXT='https://github.com/tobetter/linux'
		KERNEL_NEXT_BRANCH="odroidxu4-v4.2"
		KERNEL_NEXT_SOURCE="linux-odroidxu-next"
		UBOOT_DEFAULT="https://github.com/hardkernel/u-boot.git"
		UBOOT_DEFAULT_BRANCH="odroidxu3-v2012.07"
		UBOOT_DEFAULT_SOURCE="u-boot-odroidxu"
		UBOOT_NEXT=$UBOOT_DEFAULT
		UBOOT_NEXT_BRANCH=$UBOOT_DEFAULT_BRANCH
		UBOOT_NEXT_SOURCE=$UBOOT_DEFAULT_SOURCE
		UBOOT_DEV=$UBOOT_DEFAULT
		UBOOT_DEV_BRANCH=$UBOOT_DEFAULT_BRANCH
		UBOOT_DEV_SOURCE=$UBOOT_DEFAULT_SOURCE
	;;

	odroidc1)
		KERNEL_DEFAULT='https://github.com/hardkernel/linux'
		KERNEL_DEFAULT_BRANCH="odroidc-3.10.y"
		KERNEL_DEFAULT_SOURCE="linux-odroidc1"
		KERNEL_NEXT='https://github.com/tobetter/linux'
		KERNEL_NEXT_BRANCH="odroidxu4-v4.2"
		KERNEL_NEXT_SOURCE="linux-odroidxu-next"
		UBOOT_DEFAULT="https://github.com/hardkernel/u-boot.git"
		UBOOT_DEFAULT_BRANCH="odroidc-v2011.03"
		UBOOT_DEFAULT_SOURCE="u-boot-odroidc1"
		UBOOT_NEXT=$UBOOT_DEFAULT
		UBOOT_NEXT_BRANCH=$UBOOT_DEFAULT_BRANCH
		UBOOT_NEXT_SOURCE=$UBOOT_DEFAULT_SOURCE
		UBOOT_DEV=$UBOOT_DEFAULT
		UBOOT_DEV_BRANCH=$UBOOT_DEFAULT_BRANCH
		UBOOT_DEV_SOURCE=$UBOOT_DEFAULT_SOURCE
	;;
	
	odroidc2)
		KERNEL_DEFAULT='https://github.com/hardkernel/linux'
		KERNEL_DEFAULT_BRANCH="odroidc2-3.14.y"
		KERNEL_DEFAULT_SOURCE="linux-odroidc2"
		KERNEL_NEXT='https://github.com/hardkernel/linux'
		KERNEL_NEXT_BRANCH="odroidc2-3.14.y"
		KERNEL_NEXT_SOURCE="linux-odroidc2-next"
		UBOOT_DEFAULT="https://github.com/hardkernel/u-boot.git"
		UBOOT_DEFAULT_BRANCH="odroidc2-v2015.01"
		UBOOT_DEFAULT_SOURCE="u-boot-odroidc2"
		UBOOT_NEXT=$UBOOT_DEFAULT
		UBOOT_NEXT_BRANCH=$UBOOT_DEFAULT_BRANCH
		UBOOT_NEXT_SOURCE=$UBOOT_DEFAULT_SOURCE
		UBOOT_DEV=$UBOOT_DEFAULT
		UBOOT_DEV_BRANCH=$UBOOT_DEFAULT_BRANCH
		UBOOT_DEV_SOURCE=$UBOOT_DEFAULT_SOURCE
	;;
	
	udoo)
		KERNEL_DEFAULT="https://github.com/UDOOboard/linux_kernel"
		KERNEL_DEFAULT_BRANCH="3.14-1.0.x-udoo"
		KERNEL_DEFAULT_SOURCE="linux-udoo"
		KERNEL_NEXT="https://github.com/patrykk/linux-udoo"
		KERNEL_NEXT_BRANCH="v4.4.0-6-vivante-5.0.11.p7.3"
		KERNEL_NEXT_SOURCE="linux-udoo-next"
		UBOOT_DEFAULT="https://github.com/UDOOboard/uboot-imx"
		UBOOT_DEFAULT_BRANCH="2015.10.fslc-qdl"
		UBOOT_DEFAULT_SOURCE="u-boot-udoo"
		UBOOT_NEXT=$UBOOT_DEFAULT
		UBOOT_NEXT_BRANCH=$UBOOT_DEFAULT_BRANCH
		UBOOT_NEXT_SOURCE=$UBOOT_DEFAULT_SOURCE
		UBOOT_DEV=$UBOOT_DEFAULT
		UBOOT_DEV_BRANCH=$UBOOT_DEFAULT_BRANCH
		UBOOT_DEV_SOURCE=$UBOOT_DEFAULT_SOURCE
	;;

	neo)
		KERNEL_DEFAULT='https://github.com/UDOOboard/linux_kernel'
		#KERNEL_DEFAULT_BRANCH="imx_3.14.28_1.0.0_ga_neo"
		KERNEL_DEFAULT_BRANCH="3.14-1.0.x-udoo"
		#KERNEL_DEFAULT_SOURCE="linux-udoo-neo"
		KERNEL_DEFAULT_SOURCE="linux-udoo"
		UBOOT_DEFAULT="https://github.com/UDOOboard/uboot-imx"
		UBOOT_DEFAULT_BRANCH="2015.04.imx-neo"
		UBOOT_DEFAULT_SOURCE="u-boot-neo"
		UBOOT_NEXT=$UBOOT_DEFAULT
		UBOOT_NEXT_BRANCH=$UBOOT_DEFAULT_BRANCH
		UBOOT_NEXT_SOURCE=$UBOOT_DEFAULT_SOURCE
		UBOOT_DEV=$UBOOT_DEFAULT
		UBOOT_DEV_BRANCH=$UBOOT_DEFAULT_BRANCH
		UBOOT_DEV_SOURCE=$UBOOT_DEFAULT_SOURCE
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
		UBOOT_DEFAULT="https://github.com/SolidRun/u-boot-imx6"
		UBOOT_DEFAULT_BRANCH="imx6"
		UBOOT_DEFAULT_SOURCE="u-boot-cubox"
		UBOOT_NEXT=$UBOOT_DEFAULT
		UBOOT_NEXT_BRANCH=$UBOOT_DEFAULT_BRANCH
		UBOOT_NEXT_SOURCE=$UBOOT_DEFAULT_SOURCE
		UBOOT_DEV=$UBOOT_DEFAULT
		UBOOT_DEV_BRANCH=$UBOOT_DEFAULT_BRANCH
		UBOOT_DEV_SOURCE=$UBOOT_DEFAULT_SOURCE
	;;

	s500)		
		KERNEL_DEFAULT='https://github.com/LeMaker/linux-actions'
		KERNEL_DEFAULT_BRANCH="linux-3.10.y"
		KERNEL_DEFAULT_SOURCE="linux-s500"
		UBOOT_DEFAULT="https://github.com/LeMaker/u-boot-actions"
		UBOOT_DEFAULT_BRANCH="s500-master"
		UBOOT_DEFAULT_SOURCE="u-boot-s500"
		UBOOT_NEXT=$UBOOT_DEFAULT
		UBOOT_NEXT_BRANCH=$UBOOT_DEFAULT_BRANCH
		UBOOT_NEXT_SOURCE=$UBOOT_DEFAULT_SOURCE
		UBOOT_DEV=$UBOOT_DEFAULT
		UBOOT_DEV_BRANCH=$UBOOT_DEFAULT_BRANCH
		UBOOT_DEV_SOURCE=$UBOOT_DEFAULT_SOURCE
	;;

	toradex)
		KERNEL_DEFAULT="git://git.toradex.com/linux-toradex.git"
		KERNEL_DEFAULT_BRANCH="toradex_imx_3.14.28_1.0.0_ga"
		KERNEL_DEFAULT_SOURCE="linux-toradex"
		UBOOT_DEFAULT="git://git.toradex.com/u-boot-toradex.git"
		UBOOT_DEFAULT_BRANCH="2015.04-toradex"
		UBOOT_DEFAULT_SOURCE="u-boot-toradex"
		UBOOT_NEXT=$UBOOT_DEFAULT
		UBOOT_NEXT_BRANCH=$UBOOT_DEFAULT_BRANCH
		UBOOT_NEXT_SOURCE=$UBOOT_DEFAULT_SOURCE
		UBOOT_DEV=$UBOOT_DEFAULT
		UBOOT_DEV_BRANCH=$UBOOT_DEFAULT_BRANCH
		UBOOT_DEV_SOURCE=$UBOOT_DEFAULT_SOURCE
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
		UBOOT_DEFAULT="https://github.com/SolidRun/u-boot-armada38x"
		UBOOT_DEFAULT_BRANCH="u-boot-2013.01-15t1-clearfog"
		UBOOT_DEFAULT_SOURCE="u-boot-armada"
		UBOOT_NEXT=$UBOOT_DEFAULT
		UBOOT_NEXT_BRANCH=$UBOOT_DEFAULT_BRANCH
		UBOOT_NEXT_SOURCE=$UBOOT_DEFAULT_SOURCE
		UBOOT_DEV=$UBOOT_DEFAULT
		UBOOT_DEV_BRANCH=$UBOOT_DEFAULT_BRANCH
		UBOOT_DEV_SOURCE=$UBOOT_DEFAULT_SOURCE
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
[[ -z $CPUMIN && $LINUXFAMILY == cubox ]] && CPUMIN="396000" && CPUMAX="996000" && GOVERNOR="interactive"
[[ -z $CPUMIN && $LINUXFAMILY == s500 ]] && CPUMIN="408000" && CPUMAX="1104000" && GOVERNOR="interactive"
[[ -z $CPUMIN && $LINUXFAMILY == marvell ]] && CPUMIN="800000" && CPUMAX="1600000" && GOVERNOR="ondemand"
[[ -z $CPUMIN && ($LINUXFAMILY == udoo || $LINUXFAMILY == neo ) ]] && CPUMIN="392000" && CPUMAX="996000" && GOVERNOR="interactive"
[[ -z $GOVERNOR ]] && GOVERNOR="ondemand"

case $ARCH in
	arm64)
	TARGETS=Image
	CROSS_COMPILE="$CCACHE aarch64-linux-gnu-"
	ARCHITECTURE=arm64
	;;

	armhf)
	TARGETS=zImage
	CROSS_COMPILE="$CCACHE arm-linux-gnueabihf-"
	ARCHITECTURE=arm
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

