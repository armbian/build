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


# vaid options for automatic building
#
# build 0 = don't build
# build 1 = old kernel
# build 2 = next kernel
# build 3 = both kernels


#---------------------------------------------------------------------------------------------------------------------------------
# common options
#---------------------------------------------------------------------------------------------------------------------------------


REVISION="4.71" 										# all boards have same revision
SDSIZE="4000" 											# SD image size in MB
TZDATA=`cat /etc/timezone`								# Timezone for target is taken from host or defined here.
USEALLCORES="yes"                           			# Use all CPU cores for compiling
SYSTEMD="no"											# Enable or disable systemd on Jessie. 
OFFSET="1" 												# Bootloader space in MB (1 x 2048 = default)
BOOTSIZE="0" 											# Mb size of boot partition
UBOOTTAG="v2015.10"										# U-boot TAG
BOOTLOADER="git://git.denx.de/u-boot.git"				# mainline u-boot sources
BOOTSOURCE="u-boot"										# mainline u-boot local directory
BOOTDEFAULT="master" 									# default branch that git checkout works properly
LINUXDEFAULT="HEAD" 									# default branch that git checkout works properly
MISC1="https://github.com/linux-sunxi/sunxi-tools.git"	# Allwinner fex compiler / decompiler	
MISC1_DIR="sunxi-tools"									# local directory
MISC2=""												# Reserved
MISC2_DIR=""											# local directory
MISC3="https://github.com/dz0ny/rt8192cu --depth 1"		# Realtek drivers
MISC3_DIR="rt8192cu"									# local directory
MISC4="https://github.com/notro/fbtft"					# Small TFT display driver
MISC4_DIR="fbtft-drivers"								# local directory
MISC5="https://github.com/hglm/a10disp/ --depth 1"		# Display changer for Allwinner
MISC5_DIR="sunxi-display-changer"						# local directory


#---------------------------------------------------------------------------------------------------------------------------------
# If KERNELTAG is not defined, let's compile latest stable. Vanilla kernel only
#---------------------------------------------------------------------------------------------------------------------------------
[[ -z "$KERNELTAG" ]] && KERNELTAG="v"`wget -qO-  https://www.kernel.org/finger_banner | grep "The latest st" | awk '{print $NF}'`


#---------------------------------------------------------------------------------------------------------------------------------
# common for legacy allwinner kernel-source
#---------------------------------------------------------------------------------------------------------------------------------
# dan and me
LINUXKERNEL="https://github.com/dan-and/linux-sunxi --depth 1"
LINUXSOURCE="linux-sunxi"
LINUXFAMILY="sunxi"
LINUXCONFIG="linux-sunxi"


# linux-sunxi
LINUXKERNEL="https://github.com/linux-sunxi/linux-sunxi -b sunxi-3.4 --depth 1"
LINUXSOURCE="linux-sunxi-dev"
LINUXFAMILY="sun7i"
LINUXCONFIG="linux-sun7i"

CPUMIN="480000"
CPUMAX="1010000"


#---------------------------------------------------------------------------------------------------------------------------------
# choose configuration
#---------------------------------------------------------------------------------------------------------------------------------
case $BOARD in


cubieboard4)#disabled
#---------------------------------------------------------------------------------------------------------------------------------
# Cubieboards 3.4.x
#---------------------------------------------------------------------------------------------------------------------------------
OFFSET="20"
BOOTSIZE="16"
BOOTCONFIG="Bananapi_defconfig" # we don't use it. binnary
CPUMIN="1200000"
CPUMAX="1800000"
LINUXFAMILY="sun9i"
LINUXKERNEL="https://github.com/cubieboard/CC-A80-kernel-source"
LINUXSOURCE="linux-sun9i"
LINUXCONFIG="linux-sun9i"
;;


aw-som-a20)#enabled
#description A20 dual core SoM
#build 0
#---------------------------------------------------------------------------------------------------------------------------------
# https://aw-som.com/
#---------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="Awsom_defconfig" 
MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i"
MODULES_NEXT="bonding"
;;


cubieboard)#enabled
#description A10 single core 1Gb SoC
#build 3
#---------------------------------------------------------------------------------------------------------------------------------
# Cubieboard
#---------------------------------------------------------------------------------------------------------------------------------
LINUXFAMILY="sun4i"
LINUXCONFIG="linux-sun4i"
BOOTCONFIG="Cubieboard_config" 
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sunxi"
MODULES_NEXT="bonding"
;;


cubieboard2)#enabled
#description A20 dual core 1Gb SoC
#build 3
#---------------------------------------------------------------------------------------------------------------------------------
# Cubieboard
#---------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="Cubieboard2_config" 
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i"
MODULES_NEXT="bonding"
;;


cubietruck)#enabled
#description A20 dual core 2Gb SoC Wifi
#build 3
#---------------------------------------------------------------------------------------------------------------------------------
# Cubieboard
#---------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="Cubietruck_config" 
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i ap6210"
MODULES_NEXT="brcmfmac rfcomm hidp bonding"
;;


lime-a10)#enabled
#description A10 single core 512Mb SoC
#build 3
#---------------------------------------------------------------------------------------------------------------------------------
# Olimex Lime
#---------------------------------------------------------------------------------------------------------------------------------
LINUXKERNEL="https://github.com/linux-sunxi/linux-sunxi"
LINUXSOURCE="linux-sunxi-dev"
LINUXFAMILY="sun4i"
LINUXCONFIG="linux-sun4i"
BOOTCONFIG="A10-OLinuXino-Lime_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i 8021q a20_tp"
MODULES_NEXT="bonding"
;;


lime)#enabled
#description A20 dual core 512Mb SoC
#build 3
#---------------------------------------------------------------------------------------------------------------------------------
# Olimex Lime
#---------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="A20-OLinuXino-Lime_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i 8021q a20_tp"
MODULES_NEXT="bonding"
;;


lime2)#enabled
#description A20 dual core 1Gb SoC
#build 3
#---------------------------------------------------------------------------------------------------------------------------------
# Olimex Lime 2
#---------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="A20-OLinuXino-Lime2_defconfig" 
MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i 8021q a20_tp"
MODULES_NEXT="bonding"
;;


micro)#enabled
#description A20 dual core 1Gb SoC	
#build 3
#---------------------------------------------------------------------------------------------------------------------------------
# Olimex Lime mainline kernel	/ experimental
#---------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="A20-OLinuXino_MICRO_config"
MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i 8021q a20_tp"
MODULES_NEXT="bonding"
;;


pcduino3nano)#enabled
#description A20 dual core 1Gb SoC
#build 3
#---------------------------------------------------------------------------------------------------------------------------------
# pcduino3nano
#---------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="Linksprite_pcDuino3_Nano_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i"
MODULES_NEXT="bonding"
;;


bananapim2)#enabled
#description A31 quad core 1Gb SoC Wifi
#build 2
#---------------------------------------------------------------------------------------------------------------------------------
# Bananapi M2
#---------------------------------------------------------------------------------------------------------------------------------
BOOTLOADER="https://github.com/BPI-SINOVOIP/BPI-Mainline-uboot"
BOOTCONFIG="Bananapi_M2_defconfig"
BOOTSOURCE="u-boot-bpi-m2"
BOOTDEFAULT="master"
UBOOTTAG=""
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i 8021q a20_tp"
MODULES_NEXT="brcmfmac bonding"
;;


bananapi)#enabled
#description A20 dual core 1Gb SoC
#build 3
#---------------------------------------------------------------------------------------------------------------------------------
# Bananapi
#---------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="Bananapi_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i 8021q a20_tp"
MODULES_NEXT="brcmfmac bonding"
;;


bananapipro)#enabled
#description A20 dual core 1Gb SoC Wifi
#build 0
#---------------------------------------------------------------------------------------------------------------------------------
# Bananapi
#---------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="Bananapro_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i 8021q a20_tp ap6210"
MODULES_NEXT="brcmfmac bonding"
;;


lamobo-r1)#enabled
#description A20 dual core 1Gb SoC Switch
#build 3
#---------------------------------------------------------------------------------------------------------------------------------
# Bananapi
#---------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="Lamobo_R1_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i 8021q"
MODULES_NEXT="brcmfmac bonding"
;;


orangepi)#enabled
#description A20 dual core 1Gb SoC Wifi USB hub
#build 3
#---------------------------------------------------------------------------------------------------------------------------------
# Bananapi
#---------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="Orangepi_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i 8021q a20_tp"
MODULES_NEXT="bonding"
;;


orangepimini)#enabled
#description A20 dual core 1Gb SoC Wifi
#build 0
#---------------------------------------------------------------------------------------------------------------------------------
# Bananapi
#---------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="Orangepi_mini_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i 8021q a20_tp"
MODULES_NEXT="bonding"
;;


orangepiplus)#enabled
#description H3 quad core 1Gb SoC Wifi USB hub
#build 2wip
#---------------------------------------------------------------------------------------------------------------------------------
# Orange pi plus H3
#---------------------------------------------------------------------------------------------------------------------------------
KERNELTAG="v4.4-rc2"
BOOTCONFIG="orangepi_plus_defconfig"
LINUXFAMILY="sun8i"
CPUMIN="1200000"
CPUMAX="1200000"
UBOOTTAG=""
LINUXCONFIG="linux-sunxi-dev"
;;


cubox-i)#enabled
#description Freescale iMx dual/quad core Wifi
#build 1
#---------------------------------------------------------------------------------------------------------------------------------
# cubox-i & hummingboard 3.14.xx
#---------------------------------------------------------------------------------------------------------------------------------
BOOTLOADER="https://github.com/SolidRun/u-boot-imx6 --depth 1"
BOOTDEFAULT="HEAD"
UBOOTTAG=""
BOOTSOURCE="u-boot-cubox"
BOOTCONFIG="mx6_cubox-i_config"
CPUMIN="396000"
CPUMAX="996000"
MODULES="bonding"
MODULES_NEXT="bonding"
LINUXKERNEL="https://github.com/linux4kix/linux-linaro-stable-mx6 --depth 1"
LINUXFAMILY="cubox"
LINUXCONFIG="linux-cubox"
LINUXSOURCE="linux-cubox"
if [[ $BRANCH == *next* ]];then
	LINUXKERNEL="git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git"
	LINUXSOURCE="linux-mainline"
	LINUXCONFIG="linux-cubox-next"
fi
;;


udoo)#enabled
#description Freescale iMx dual/quad core Wifi
#build 3
#---------------------------------------------------------------------------------------------------------------------------------
# Udoo quad
#---------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="udoo_quad_config"
BOOTLOADER="https://github.com/UDOOboard/uboot-imx"
BOOTSOURCE="u-boot-neo"
UBOOTTAG=""
BOOTDEFAULT="master"
CPUMIN="392000"
CPUMAX="996000"
MODULES="bonding"
MODULES_NEXT=""
KERNELTAG=""
LINUXKERNEL="https://github.com/UDOOboard/linux_kernel --depth 1"
LINUXCONFIG="linux-udoo"
LINUXSOURCE="linux-udoo"
LINUXDEFAULT="3.14-1.0.x-udoo"
LINUXFAMILY="udoo"
;;


udoo-neo)#enabled
#description Freescale iMx singe core Wifi
#build 0
#---------------------------------------------------------------------------------------------------------------------------------
# Udoo Neo
#---------------------------------------------------------------------------------------------------------------------------------
#BOOTSIZE="32"
BOOTCONFIG="udoo_neo_config"
BOOTLOADER="https://github.com/UDOOboard/uboot-imx"
BOOTSOURCE="u-boot-neo"
UBOOTTAG=""
CPUMIN="198000"
CPUMAX="996000"
MODULES="bonding"
MODULES_NEXT=""
LINUXKERNEL="--depth 1 https://github.com/UDOOboard/linux_kernel -b imx_3.14.28_1.0.0_ga_neo_dev"
LINUXCONFIG="linux-udoo-neo"
LINUXSOURCE="linux-neo"
LINUXFAMILY="neo"
;;


guitar)#enabled
#description S500 Lemaker Guitar Action quad core
#build 1wip
#---------------------------------------------------------------------------------------------------------------------------------
# Lemaker Guitar
#---------------------------------------------------------------------------------------------------------------------------------
OFFSET="16" 
BOOTSIZE="16"
BOOTCONFIG="s500_defconfig"
BOOTLOADER="https://github.com/LeMaker/u-boot-actions"
BOOTSOURCE="u-boot-guitar"
UBOOTTAG=""
CPUMIN="198000"
CPUMAX="996000"
MODULES="ethernet wlan_8723bs bonding"
MODULES_NEXT=""
LINUXKERNEL="https://github.com/LeMaker/linux-actions --depth 1"
LINUXCONFIG="linux-guitar"
LINUXSOURCE="linux-guitar"
LINUXFAMILY="s500"
;;


rpi)#disabled
#---------------------------------------------------------------------------------------------------------------------------------
# RPi
#---------------------------------------------------------------------------------------------------------------------------------
BOOTSIZE="32"
BOOTLOADER="https://github.com/UDOOboard/uboot-imx"
BOOTSOURCE="u-boot-neo"
BOOTCONFIG="udoo_neo_config"
CPUMIN="198000"
CPUMAX="996000"
MODULES="bonding"
MODULES_NEXT=""
LINUXKERNEL="https://github.com/raspberrypi/linux"
LINUXCONFIG="linux-rpi.config"
LINUXSOURCE="linux-rpi"
LINUXFAMILY="rpi"
;;



*) echo "Board configuration not found"
exit
;;
esac


#---------------------------------------------------------------------------------------------------------------------------------
# Vanilla Linux, second option, ...
#---------------------------------------------------------------------------------------------------------------------------------
if [[ $BRANCH == *next* ]];then
	# All next compilations are using mainline u-boot & kernel
	LINUXKERNEL="git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git --depth 1"
	LINUXSOURCE="linux-mainline"
	LINUXCONFIG="linux-sunxi-next"
	LINUXDEFAULT="master"
	LINUXFAMILY="sunxi"
	FIRMWARE=""
	#LINUXSOURCE="linux-mainline-dac"
	#LINUXKERNEL="https://github.com/ssvb/linux-sunxi -b 20151014-4.3.0-rc5-pcduino2-otg-test --depth 1"
	#LINUXCONFIG="linux-sunxi-dac"
	#KERNELTAG=""
	
	
	if [[ $BOARD == "udoo" ]];then
	LINUXKERNEL="https://github.com/patrykk/linux-udoo --depth 1"
	LINUXSOURCE="linux-udoo-next"
	LINUXCONFIG="linux-udoo-next"
	LINUXDEFAULT="HEAD"
	KERNELTAG=""
	LINUXFAMILY="udoo"
	fi
fi