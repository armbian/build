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
# Board configurations
#
#


# vaid options for automatic building and menu selection
#
# build 0 = don't build
# build 1 = old kernel
# build 2 = next kernel
# build 3 = both kernels
# build 4 = dev kernel
# build 5 = next and dev kernels
# build 6 = legacy and next and dev kernel


# common options

REVISION="5.05" # all boards have same revision
ROOTPWD="1234" # Must be changed @first login
MAINTAINER="Igor Pecovnik" # deb signature
MAINTAINERMAIL="igor.pecovnik@****l.com" # deb signature
SDSIZE="4000" # SD image size in MB
TZDATA=`cat /etc/timezone` # Timezone for target is taken from host or defined here.
USEALLCORES="yes" # Use all CPU cores for compiling
SYSTEMD="no" # Enable or disable systemd on Jessie in debootstrap process 
OFFSET="1" # Bootloader space in MB (1 x 2048 = default)
BOOTSIZE="0" # Mb size of boot partition
EXIT_PATCHING_ERROR="" # exit patching if failed
SERIALCON="ttyS0"
MISC1="https://github.com/linux-sunxi/sunxi-tools.git" # Allwinner fex compiler / decompiler	
MISC1_DIR="sunxi-tools"	# local directory
MISC2="" # Reserved
MISC2_DIR="" # local directory
MISC3="https://github.com/dz0ny/rt8192cu" # Realtek drivers
MISC3_DIR="rt8192cu" # local directory
MISC4=""
MISC4_DIR=""
MISC5="https://github.com/hglm/a10disp/" # Display changer for Allwinner
MISC5_DIR="sunxi-display-changer" # local directory
MISC6="https://github.com/porjo/mt7601/" # Display changer for Allwinner
MISC6_DIR="mt7601" # local directory



# board configurations

case $BOARD in

	cubieboard4)#disabled
		LINUXFAMILY="sun9i"		
		BOOTCONFIG="Cubieboard4_defconfig"
		CPUMIN="1200000"
		CPUMAX="1800000"
		GOVERNOR="ondemand"
	;;

	aw-som-a20)#enabled
		#description A20 dual core SoM
		#build 0
		LINUXFAMILY="sun7i"
		BOOTCONFIG="Awsom_defconfig" 
		MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i"
		MODULES_NEXT="bonding"
	;;

	olinux-som-a13)#enabled
		#description A13 single core 512Mb SoM
		#build 0
		LINUXFAMILY="sun5i"		
		BOOTCONFIG="A13-OLinuXino_defconfig" 
		MODULES="gpio_sunxi spi_sunxi"
		MODULES_NEXT="bonding"
	;;

	cubieboard)#enabled
		#description A10 single core 1Gb SoC
		#build 6
		LINUXFAMILY="sun4i"
		BOOTCONFIG="Cubieboard_config"
		MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sunxi"
		MODULES_NEXT="bonding"
		DESKTOP_TARGET="trusty,default"
	;;

	cubieboard2)#enabled
		#description A20 dual core 1Gb SoC
		#build 6
		LINUXFAMILY="sun7i"
		BOOTCONFIG="Cubieboard2_config" 
		MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i"
		MODULES_NEXT="bonding"
		DESKTOP_TARGET="trusty,default"
	;;

	cubietruck)#enabled
		#description A20 dual core 2Gb SoC Wifi
		#build 6
		LINUXFAMILY="sun7i"
		BOOTCONFIG="Cubietruck_config" 
		MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i ap6210"
		MODULES_NEXT="brcmfmac rfcomm hidp bonding"
		DESKTOP_TARGET="trusty,%"
	;;

	lime-a10)#enabled
		#description A10 single core 512Mb SoC
		#build 6
		LINUXFAMILY="sun4i"
		BOOTCONFIG="A10-OLinuXino-Lime_defconfig"
		MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i 8021q a20_tp"
		MODULES_NEXT="bonding"
		DESKTOP_TARGET="trusty,next"
	;;

	lime)#enabled
		#description A20 dual core 512Mb SoC
		#build 6
		LINUXFAMILY="sun7i"
		BOOTCONFIG="A20-OLinuXino-Lime_defconfig"
		MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i 8021q a20_tp"
		MODULES_NEXT="bonding"
		DESKTOP_TARGET="trusty,default"
	;;

	lime2)#enabled
		#description A20 dual core 1Gb SoC
		#build 6
		LINUXFAMILY="sun7i"
		BOOTCONFIG="A20-OLinuXino-Lime2_defconfig" 
		MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i 8021q a20_tp"
		MODULES_NEXT="bonding"
		DESKTOP_TARGET="trusty,default"
	;;

	micro)#enabled
		#description A20 dual core 1Gb SoC
		#build 6
		LINUXFAMILY="sun7i"
		BOOTCONFIG="A20-OLinuXino_MICRO_config"
		MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i 8021q a20_tp"
		MODULES_NEXT="bonding"
		DESKTOP_TARGET="trusty,default"
	;;

	pcduino3nano)#enabled
		#description A20 dual core 1Gb SoC
		#build 6
		LINUXFAMILY="sun7i"
		BOOTCONFIG="Linksprite_pcDuino3_Nano_defconfig"
		MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i"
		MODULES_NEXT="bonding"
		DESKTOP_TARGET="trusty,default"
	;;

	bananapim2)#enabled
		#description A31 quad core 1Gb SoC Wifi
		#build 5
		LINUXFAMILY="sun6i"
		BOOTCONFIG="Sinovoip_BPI_M2_defconfig"
		MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i 8021q a20_tp"
		MODULES_NEXT="brcmfmac bonding"
		DESKTOP_TARGET="trusty,next"
	;;

	bananapipro)#enabled
		#description A20 dual core 1Gb SoC
		#build 6
		LINUXFAMILY="sun7i"
		BOOTCONFIG="Bananapro_defconfig"
		MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i 8021q a20_tp #ap6211"
		MODULES_NEXT="brcmfmac bonding"
		DESKTOP_TARGET="trusty,%"
	;;

	lamobo-r1)#enabled
		#description A20 dual core 1Gb SoC Switch
		#build 6
		LINUXFAMILY="sun7i"
		BOOTCONFIG="Lamobo_R1_defconfig"
		MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i 8021q"
		MODULES_NEXT="brcmfmac bonding"			
	;;

	orangepi)#enabled
		#description A20 dual core 1Gb SoC Wifi USB hub
		#build 6
		LINUXFAMILY="sun7i"
		BOOTCONFIG="Orangepi_defconfig"
		MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i 8021q a20_tp"
		MODULES_NEXT="bonding"
		DESKTOP_TARGET="trusty,%"
	;;

	orangepimini)#enabled
		#description A20 dual core 1Gb SoC Wifi
		#build 0
		LINUXFAMILY="sun7i"
		BOOTCONFIG="Orangepi_mini_defconfig"
		MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i 8021q a20_tp"
		MODULES_NEXT="bonding"
	;;

	orangepiplus)#enabled
		#description H3 quad core (Orange Pi Plus or Plus 2)
		#build 3wip
		LINUXFAMILY="sun8i"
		BOOTCONFIG="orangepi_plus_defconfig"
		MODULES="8189es #gpio_sunxi #w1-sunxi #w1-gpio #w1-therm #gc2035"
		MODULES_NEXT=""
		CPUMIN="480000"
		CPUMAX="1296000"
		GOVERNOR="interactive"
	;;

	orangepih3)#enabled
		#description H3 quad core (Orange Pi PC/One/2/Lite)
		#build 3wip
		LINUXFAMILY="sun8i"
		BOOTCONFIG="orangepi_h3_defconfig"
		MODULES="8189es #gpio_sunxi #w1-sunxi #w1-gpio #w1-therm #gc2035"
		MODULES_NEXT=""
		CPUMIN="480000"
		CPUMAX="1296000"
		GOVERNOR="interactive"
	;;

	bananapim2plus)#disabled
		# description H3 quad core 1Gb SoC Wifi
		LINUXFAMILY="sun8i"
		BOOTCONFIG="bananapim2_plus_defconfig"
		MODULES="ap6210 #gpio_sunxi #w1-sunxi #w1-gpio #w1-therm"
		MODULES_NEXT="brcmfmac"
		CPUMIN="0"
		CPUMAX="0"
		GOVERNOR="interactive"
	;;

	cubox-i)#enabled
		#description Freescale iMx dual/quad core Wifi
		#build 6
		LINUXFAMILY="cubox"
		BOOTCONFIG="mx6_cubox-i_config"
		MODULES="bonding"
		MODULES_NEXT="bonding"
		SERIALCON="ttymxc0"
		DESKTOP_TARGET="jessie,default"
	;;

	udoo)#enabled
		#description Freescale iMx dual/quad core Wifi
		#build 3
		LINUXFAMILY="udoo"
		BOOTCONFIG="udoo_qdl_config"
		MODULES="bonding"
		MODULES_NEXT=""
		SERIALCON="ttymxc1"
		DESKTOP_TARGET="jessie,%"
	;;

	udoo-neo)#enabled
		#description Freescale iMx singe core Wifi
		#build 1
		#BOOTSIZE="32"
		LINUXFAMILY="neo"
		BOOTCONFIG="udoo_neo_config"
		MODULES="bonding"
		MODULES_NEXT=""
		SERIALCON="ttymxc0"
	;;

	guitar)#enabled
		#description S500 Lemaker Guitar Action quad core
		#build 0
		LINUXFAMILY="s500"
		OFFSET="16"
		BOOTSIZE="16"
		BOOTCONFIG="s500_defconfig"
		MODULES="ethernet wlan_8723bs"
		MODULES_NEXT=""
		SERIALCON="ttyS3"
	;;

	odroidxu4)#enabled
		#description Exynos5422 XU3/XU4 octa core
		#build 1
		LINUXFAMILY="odroidxu4"
		BOOTSIZE="16"
		BOOTCONFIG="odroid_config"
		MODULES="bonding"
		MODULES_NEXT=""
		SERIALCON="ttySAC2"
		DESKTOP_TARGET="jessie,default"
	;;

	toradex)#disabled
		LINUXFAMILY="toradex"
		BOOTCONFIG="colibri_imx6_defconfig"
		MODULES=""
		MODULES_NEXT=""
		SERIALCON="ttymxc0"
	;;
	
	armada)#enabled
		#description Marvell Armada 38x
		#build 3
		LINUXFAMILY="marvell"
		BOOTCONFIG="armada_38x_clearfog_config"
		MODULES=""
		MODULES_NEXT=""
		SERIALCON="ttyS0"
	;;
	
	*) exit_with_error "Board configuration not found" "$BOARD"
	;;
esac



# board family configurations
case $LINUXFAMILY in

	sun4i|sun5i|sun7i|sun8i|sun6i|sun9i)
		[[ -z $LINUXCONFIG && $BRANCH == "default" ]] && LINUXCONFIG="linux-"$LINUXFAMILY-"$BRANCH"
		[[ -z $LINUXCONFIG && $BRANCH != "default" ]] && LINUXCONFIG="linux-sunxi-"$BRANCH
		# Kernel
		KERNEL_DEFAULT='https://github.com/linux-sunxi/linux-sunxi'
		KERNEL_DEFAULT_BRANCH="sunxi-3.4"
		KERNEL_DEFAULT_SOURCE="linux-sunxi"			
		# sun8i legacy
		if [[ $LINUXFAMILY == sun8i ]]; then
			# KERNEL_DEFAULT="https://github.com/ssvb/linux-sunxi"
			# KERNEL_DEFAULT_BRANCH="20151207-embedded-lima-memtester-h3"
			KERNEL_DEFAULT="https://github.com/O-Computers/linux-sunxi"
			KERNEL_DEFAULT_BRANCH="h3-wip"
			KERNEL_DEFAULT_SOURCE="linux-sun8i"
		fi			
		KERNEL_NEXT='git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git'
		[ "$USE_MAINLINE_GOOGLE_MIRROR" = "yes" ] && KERNEL_NEXT='https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux-stable'
		KERNEL_NEXT_BRANCH="v"`wget -qO-  https://www.kernel.org/finger_banner | grep "The latest st" | awk '{print $NF}' | head -1`
		KERNEL_NEXT_SOURCE="linux-vanilla"
		KERNEL_DEV='git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git'
		[ "$USE_MAINLINE_GOOGLE_MIRROR" = "yes" ] && KERNEL_DEV='https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux-stable'
		KERNEL_DEV_BRANCH=""
		KERNEL_DEV_SOURCE="linux-vanilla"
		# U-boot
		UBOOT_DEFAULT="git://git.denx.de/u-boot.git"
		if [[ $LINUXFAMILY == sun8i ]]; then
			UBOOT_DEFAULT_BRANCH="v2016.03-rc2"
		else
			UBOOT_DEFAULT_BRANCH="v"$(git ls-remote git://git.denx.de/u-boot.git | grep -v rc | grep -v "\^" | tail -1 | cut -d "v" -f 2)
		fi
		UBOOT_DEFAULT_SOURCE="u-boot"
		UBOOT_NEXT=$UBOOT_DEFAULT
		UBOOT_NEXT_BRANCH=$UBOOT_DEFAULT_BRANCH
		UBOOT_NEXT_SOURCE=$UBOOT_DEFAULT_SOURCE
		UBOOT_DEV=$UBOOT_DEFAULT
		UBOOT_DEV_BRANCH=""
		UBOOT_DEV_SOURCE=$UBOOT_DEFAULT_SOURCE
	;;
	
	odroidxu4)
		KERNEL_DEFAULT='https://github.com/hardkernel/linux'
		KERNEL_DEFAULT_BRANCH="odroidxu3-3.10.y"
		KERNEL_DEFAULT_SOURCE="linux-odroidxu"
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
		KERNEL_DEFAULT_BRANCH="s500-master"
		KERNEL_DEFAULT_SOURCE="linux-s500"
		KERNEL_NEXT='https://github.com/LeMaker/linux-actions'
		KERNEL_NEXT_BRANCH="linux-3.10.y"
		KERNEL_NEXT_SOURCE="linux-s500"
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
	
	*) exit_with_error "Defaults not found" "$LINUXFAMILY"
	;;
esac


# Let's set defalt data if not defined in board configuration above
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


# Essential packages
PACKAGE_LIST="alsa-utils automake bash-completion bc bridge-utils build-essential cmake cpufrequtils \
	device-tree-compiler dosfstools figlet fbset fping git haveged hdparm hostapd ifenslave-2.6 psmisc \
	iw less libtool libwrap0-dev libfuse2 libssl-dev lirc lsof makedev fake-hwclock wpasupplicant \
	module-init-tools nano ntp parted pkg-config pv rfkill rsync sudo curl dialog \
	sysfsutils toilet u-boot-tools unattended-upgrades unzip usbutils vlan wireless-tools wget \
	iptables libdigest-sha-perl libproc-processtable-perl w-scan libusb-dev ncurses-term \
	console-setup console-data kbd console-common unicode-data openssh-server man-db libmtp-runtime"

# Non-essential packages
PACKAGE_LIST_ADDITIONAL="btrfs-tools bluez hddtemp i2c-tools iperf ir-keytable iotop iozone3 weather-util weather-util-data stress \
	dvb-apps sysbench libbluetooth-dev libbluetooth3 subversion screen ntfs-3g vim pciutils evtest htop mtp-tools python-smbus \
	apt-transport-https"

# Release specific packages
case $RELEASE in
	wheezy)
	PACKAGE_LIST_RELEASE="libnl-dev acpid acpi-support-base"
	;;
	jessie)
	PACKAGE_LIST_RELEASE="thin-provisioning-tools libnl-3-dev libnl-genl-3-dev libpam-systemd \
		software-properties-common python-software-properties libnss-myhostname f2fs-tools"
	;;
	trusty)
	PACKAGE_LIST_RELEASE="libnl-3-dev libnl-genl-3-dev software-properties-common python-software-properties f2fs-tools acpid"
	;;
esac

# additional desktop packages
if [[ $BUILD_DESKTOP == yes ]]; then
	# common packages
	PACKAGE_LIST_DESKTOP="xserver-xorg xserver-xorg-core xfonts-base xinit nodm x11-xserver-utils xfce4 lxtask xterm mirage radiotray wicd thunar-volman galculator \
	gtk2-engines gtk2-engines-murrine gtk2-engines-pixbuf libgtk2.0-bin gcj-jre-headless xfce4-screenshooter libgnome2-perl gksu"
	# release specific desktop packages
	case $RELEASE in
		wheezy)
		PACKAGE_LIST_DESKTOP="$PACKAGE_LIST_DESKTOP mozo pluma iceweasel icedove"
		;;
		jessie)
		PACKAGE_LIST_DESKTOP="$PACKAGE_LIST_DESKTOP mozo pluma iceweasel libreoffice-writer libreoffice-java-common icedove"
		;;
		trusty)
		PACKAGE_LIST_DESKTOP="$PACKAGE_LIST_DESKTOP libreoffice-writer libreoffice-java-common thunderbird firefox gnome-icon-theme-full tango-icon-theme gvfs-backends"
		;;
	esac
	# hardware acceleration support packages
	# cache is not LINUXCONFIG and BRANCH specific, so installing anyway
	#if [[ $LINUXCONFIG == *sun* && $BRANCH != "next" ]] &&
	PACKAGE_LIST_DESKTOP="$PACKAGE_LIST_DESKTOP xorg-dev xutils-dev x11proto-dri2-dev xutils-dev libdrm-dev libvdpau-dev"
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
