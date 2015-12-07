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

	REVISION="5.00" 										# all boards have same revision
	SDSIZE="4000" 											# SD image size in MB
	TZDATA=`cat /etc/timezone`								# Timezone for target is taken from host or defined here.
	USEALLCORES="yes"                           			# Use all CPU cores for compiling
	SYSTEMD="no"											# Enable or disable systemd on Jessie. 
	OFFSET="1" 												# Bootloader space in MB (1 x 2048 = default)
	BOOTSIZE="0" 											# Mb size of boot partition
	MISC1="https://github.com/linux-sunxi/sunxi-tools.git"	# Allwinner fex compiler / decompiler	
	MISC1_DIR="sunxi-tools"									# local directory
	MISC2=""												# Reserved
	MISC2_DIR=""											# local directory
	MISC3="https://github.com/dz0ny/rt8192cu --depth 1"		# Realtek drivers
	MISC3_DIR="rt8192cu"									# local directory
	MISC4=""
	MISC4_DIR=""
	MISC5="https://github.com/hglm/a10disp/ --depth 1"		# Display changer for Allwinner
	MISC5_DIR="sunxi-display-changer"						# local directory



	# board configurations

	case $BOARD in

		cubieboard4)#enabled
			#description A80 octa core 2Gb soc wifi
			#build 5
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

		cubieboard)#enabled
			#description A10 single core 1Gb SoC
			#build 6	
			LINUXFAMILY="sun4i"		
			BOOTCONFIG="Cubieboard_config" 
			MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sunxi"
			MODULES_NEXT="bonding"
		;;

		cubieboard2)#enabled
			#description A20 dual core 1Gb SoC
			#build 6		
			LINUXFAMILY="sun7i"
			BOOTCONFIG="Cubieboard2_config" 
			MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i"
			MODULES_NEXT="bonding"
		;;

		cubietruck)#enabled
			#description A20 dual core 2Gb SoC Wifi
			#build 6	
			LINUXFAMILY="sun7i"
			BOOTCONFIG="Cubietruck_config" 
			MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i ap6210"
			MODULES_NEXT="brcmfmac rfcomm hidp bonding"
		;;

		lime-a10)#enabled
			#description A10 single core 512Mb SoC
			#build 6		
			LINUXFAMILY="sun4i"
			BOOTCONFIG="A10-OLinuXino-Lime_defconfig"
			MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i 8021q a20_tp"
			MODULES_NEXT="bonding"
		;;

		lime)#enabled
			#description A20 dual core 512Mb SoC
			#build 6
			LINUXFAMILY="sun7i"
			BOOTCONFIG="A20-OLinuXino-Lime_defconfig"
			MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i 8021q a20_tp"
			MODULES_NEXT="bonding"
		;;

		lime2)#enabled
			#description A20 dual core 1Gb SoC
			#build 6	
			LINUXFAMILY="sun7i"
			BOOTCONFIG="A20-OLinuXino-Lime2_defconfig" 
			MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i 8021q a20_tp"
			MODULES_NEXT="bonding"
		;;

		micro)#enabled
			#description A20 dual core 1Gb SoC	
			#build 6
			LINUXFAMILY="sun7i"
			BOOTCONFIG="A20-OLinuXino_MICRO_config"
			MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i 8021q a20_tp"
			MODULES_NEXT="bonding"
		;;

		pcduino3nano)#enabled
			#description A20 dual core 1Gb SoC
			#build 6	
			LINUXFAMILY="sun7i"
			BOOTCONFIG="Linksprite_pcDuino3_Nano_defconfig"
			MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i"
			MODULES_NEXT="bonding"
		;;

		bananapim2)#enabled
			#description A31 quad core 1Gb SoC Wifi
			#build 5
			LINUXFAMILY="sun6i"
			BOOTLOADER="https://github.com/BPI-SINOVOIP/BPI-Mainline-uboot"
			BOOTCONFIG="Bananapi_M2_defconfig"
			BOOTSOURCE="u-boot-bpi-m2"	
			MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i 8021q a20_tp"
			MODULES_NEXT="brcmfmac bonding"
		;;

		bananapi)#enabled
			#description A20 dual core 1Gb SoC
			#build 6		
			LINUXFAMILY="sun7i"
			BOOTCONFIG="Bananapi_defconfig"
			MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i 8021q a20_tp"
			MODULES_NEXT="brcmfmac bonding"
		;;

		bananapipro)#enabled
			#description A20 dual core 1Gb SoC Wifi
			#build 0	
			LINUXFAMILY="sun7i"
			BOOTCONFIG="Bananapro_defconfig"
			MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i 8021q a20_tp ap6210"
			MODULES_NEXT="brcmfmac bonding"
		;;

		lamobo-r1)#enabled
			#description A20 dual core 1Gb SoC Switch
			#build 3	
			LINUXFAMILY="sun7i"
			BOOTCONFIG="Lamobo_R1_defconfig"
			MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i 8021q"
			MODULES_NEXT="brcmfmac bonding"
		;;

		orangepi)#enabled
			#description A20 dual core 1Gb SoC Wifi USB hub
			#build 3
			LINUXFAMILY="sun7i"
			BOOTCONFIG="Orangepi_defconfig"
			MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i 8021q a20_tp"
			MODULES_NEXT="bonding"
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
			#description H3 quad core 1Gb SoC Wifi USB hub
			#build 2wip
			LINUXFAMILY="sun8i"		
			BOOTCONFIG="orangepi_plus_defconfig"
		;;

		cubox-i)#enabled
			#description Freescale iMx dual/quad core Wifi
			#build 1
			LINUXFAMILY="cubox"	
			BOOTCONFIG="mx6_cubox-i_config"
			MODULES="bonding"
			MODULES_NEXT="bonding"
		;;

		udoo)#enabled
			#description Freescale iMx dual/quad core Wifi
			#build 3
			LINUXFAMILY="udoo"
			BOOTCONFIG="udoo_quad_config"
			MODULES="bonding"
			MODULES_NEXT=""	
		;;

		udoo-neo)#enabled
			#description Freescale iMx singe core Wifi
			#build 1wip	
			#BOOTSIZE="32"
			LINUXFAMILY="neo"
			BOOTCONFIG="udoo_neo_config"
			MODULES="bonding"
			MODULES_NEXT=""
		;;

		guitar)#enabled
			#description S500 Lemaker Guitar Action quad core
			#build 1wip	
			LINUXFAMILY="s500"	
			OFFSET="16" 
			BOOTSIZE="16"
			BOOTCONFIG="s500_defconfig"		
			MODULES="ethernet wlan_8723bs bonding"
			MODULES_NEXT=""
		;;
		
		odroid)#enabled
			#description Exynos5422 XU3/XU4 octa core
			#build 3wip	
			LINUXFAMILY="odroid"	
			OFFSET="16" 
			BOOTSIZE="16"
			BOOTCONFIG="odroid_config"		
			MODULES="ethernet wlan_8723bs bonding"
			MODULES_NEXT=""
		;;

		*) echo "Board configuration not found"
			exit
		;;
	esac



	# board family configurations
	case $LINUXFAMILY in
	
		sun4i|sun7i|sun6i|sun9i)
			[[ -z $LINUXCONFIG && $BRANCH == "default" ]] && LINUXCONFIG="linux-"$LINUXFAMILY-"$BRANCH"
			[[ -z $LINUXCONFIG && $BRANCH != "default" ]] && LINUXCONFIG="linux-sunxi-"$BRANCH
			# Kernel
			KERNEL_DEFAULT='https://github.com/linux-sunxi/linux-sunxi'
			KERNEL_DEFAULT_BRANCH="sunxi-3.4"
			KERNEL_DEFAULT_SOURCE="linux-sunxi"
			KERNEL_NEXT='git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git'
			KERNEL_NEXT_BRANCH="v"`wget -qO-  https://www.kernel.org/finger_banner | grep "The latest st" | awk '{print $NF}'`
			KERNEL_NEXT_SOURCE="linux-vanilla"
			KERNEL_DEV='git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git'
			KERNEL_DEV_BRANCH=""
			KERNEL_DEV_SOURCE="linux-vanilla"
			# U-boot
			UBOOT="git://git.denx.de/u-boot.git"
			UBOOT_BRANCH="v"$(git ls-remote git://git.denx.de/u-boot.git | grep -v rc | grep -v "\^" | tail -1 | cut -d "v" -f 2)
			UBOOT_SOURCE="u-boot"
		;;
	
		odroid)
			KERNEL_DEFAULT='https://github.com/hardkernel/linux'
			KERNEL_DEFAULT_BRANCH="odroidxu3-3.10.y"
			KERNEL_DEFAULT_SOURCE="linux-odroid"
			KERNEL_NEXT='https://github.com/tobetter/linux'
			KERNEL_NEXT_BRANCH="odroidxu4-v4.2"
			KERNEL_NEXT_SOURCE="linux-odroid-next"		
			UBOOT="https://github.com/hardkernel/u-boot.git"
			UBOOT_BRANCH="odroidxu3-v2012.07"
			UBOOT_SOURCE="u-boot-odroid"
		;;
		
		udoo)
			KERNEL_DEFAULT="https://github.com/UDOOboard/linux_kernel"
			KERNEL_DEFAULT_BRANCH="imx_3.14.28_1.0.0_ga_neo_dev"
			KERNEL_DEFAULT_SOURCE="linux-udoo"
			KERNEL_NEXT="https://github.com/patrykk/linux-udoo"
			KERNEL_NEXT_BRANCH="4.2-5.0.11.p7.1"
			KERNEL_NEXT_SOURCE="linux-udoo-next"		
			UBOOT="https://github.com/UDOOboard/uboot-imx"
			UBOOT_BRANCH="master"
			UBOOT_SOURCE="u-boot-neo"
		;;
		
		neo)
			KERNEL_DEFAULT='https://github.com/UDOOboard/linux_kernel'
			KERNEL_DEFAULT_BRANCH="imx_3.14.28_1.0.0_ga_neo_dev"
			KERNEL_DEFAULT_SOURCE="linux-udoo-neo"		
			UBOOT="https://github.com/UDOOboard/uboot-imx"
			UBOOT_BRANCH="master"
			UBOOT_SOURCE="u-boot-neo"
		;;
		
		cubox)
			KERNEL_DEFAULT='https://github.com/linux4kix/linux-linaro-stable-mx6'
			KERNEL_DEFAULT_BRANCH="imx_3.14.28_1.0.0_ga_neo_dev"
			KERNEL_DEFAULT_SOURCE="linux-linaro-lsk-v3.14-mx6"		
			UBOOT="https://github.com/SolidRun/u-boot-imx6"
			UBOOT_BRANCH="imx6"
			UBOOT_SOURCE="u-boot-cubox"
		;;
		
		s500)
			KERNEL_DEFAULT='https://github.com/LeMaker/linux-actions'
			KERNEL_DEFAULT_BRANCH="s500-master"
			KERNEL_DEFAULT_SOURCE="linux-s500"
			UBOOT="https://github.com/LeMaker/u-boot-actions"
			UBOOT_BRANCH="s500-master"
			UBOOT_SOURCE="u-boot-s500"
		;;	
		
		*) echo "Defaults not found"
			exit
		;;
	esac


	# Let's set defalt data if not defined in board configuration above
	[[ -z $LINUXCONFIG ]] && LINUXCONFIG="linux-$LINUXFAMILY-$BRANCH"
	[[ -z $LINUXKERNEL ]] && eval LINUXKERNEL=\$KERNEL_${BRANCH^^} 
	[[ -z $LINUXSOURCE ]] && eval LINUXSOURCE=\$KERNEL_${BRANCH^^}"_SOURCE"
	[[ -z $KERNELTAG ]] && eval KERNELTAG=\$KERNEL_${BRANCH^^}"_BRANCH"
	[[ -z $BOOTLOADER ]] && eval BOOTLOADER=\$UBOOT
	[[ -z $BOOTSOURCE ]] && eval BOOTSOURCE=\$UBOOT_SOURCE
	[[ -z $BOOTBRANCH ]] && eval BOOTBRANCH=\$UBOOT_BRANCH
	[[ -z $CPUMIN && $LINUXFAMILY == sun*i ]] && CPUMIN="480000" && CPUMAX="1010000" && GOVERNOR="interactive"
	[[ -z $CPUMIN && $LINUXFAMILY == odroid ]] && CPUMIN="600000" && CPUMAX="1800000" && GOVERNOR="conservative"
	[[ -z $CPUMIN && $LINUXFAMILY == cubox ]] && CPUMIN="396000" && CPUMAX="996000" && GOVERNOR="interactive"
	[[ -z $CPUMIN && $LINUXFAMILY == s500 ]] && CPUMIN="408000" && CPUMAX="1104000" && GOVERNOR="interactive"
	[[ -z $CPUMIN && ($LINUXFAMILY == udoo || $LINUXFAMILY == neo ) ]] && CPUMIN="392000" && CPUMAX="996000" && GOVERNOR="interactive"


# debug
echo -e "Config: $LINUXCONFIG\nKernel source: $LINUXKERNEL\nBranch: $KERNELTAG" >> $DEST/debug/install.log 
echo -e "linuxsource: $LINUXSOURCE\nOffset: $OFFSET\nbootsize: $BOOTSIZE" >> $DEST/debug/install.log 
echo -e "bootloader: $BOOTLOADER\nbootsource: $BOOTSOURCE\nbootbranch: $BOOTBRANCH" >> $DEST/debug/install.log 
echo -e "CPU $CPUMIN / $CPUMAX with $GOVERNOR" >> $DEST/debug/install.log 