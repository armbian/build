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


#--------------------------------------------------------------------------------------------------------------------------------
# common for default allwinner kernel-source
#--------------------------------------------------------------------------------------------------------------------------------

# build 0 = don't build
# build 1 = old kernel
# build 2 = next kernel
# build 3 = both kernels


SDSIZE="4000" # SD image size in MB
UBOOTTAG="v2015.07"
USEALLCORES="yes"                           # Use all CPU cores for compiling
BOOTLOADER="git://git.denx.de/u-boot.git"
BOOTSOURCE="u-boot"
LINUXKERNEL="https://github.com/dan-and/linux-sunxi"
LINUXSOURCE="linux-sunxi"
LINUXCONFIG="linux-sunxi"
LINUXFAMILY="sunxi"
CPUMIN="480000"
CPUMAX="1010000"
OFFSET="1" # MB (1 x 2048 = default)
BOOTSIZE="0" # Mb size of boot partition
BOOTDEFAULT="master" # default branch that git checkout works properly
LINUXDEFAULT="HEAD" # default branch that git checkout works properly
FIRMWARE="bin/ap6210.zip"
MISC1="https://github.com/linux-sunxi/sunxi-tools.git"		
MISC1_DIR="sunxi-tools"
MISC2=""	
MISC2_DIR=""						
MISC3="https://github.com/dz0ny/rt8192cu"	
MISC3_DIR="rt8192cu"
MISC4="https://github.com/notro/fbtft"
MISC4_DIR="fbtft-drivers"
MISC5="https://github.com/hglm/a10disp/"
MISC5_DIR="sunxi-display-changer"

#--------------------------------------------------------------------------------------------------------------------------------
# common for default allwinner kernel-source 
#--------------------------------------------------------------------------------------------------------------------------------


#--------------------------------------------------------------------------------------------------------------------------------
# choose configuration
#--------------------------------------------------------------------------------------------------------------------------------
case $BOARD in


cubieboard4)
#--------------------------------------------------------------------------------------------------------------------------------
# Cubieboards 3.4.x
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="1.0"
OFFSET="20"
BOOTSIZE="16"
BOOTCONFIG="Merrii_A80_Optimus_defconfig"
MODULES=""
MODULES_NEXT=""
CPUMIN="1200000"
CPUMAX="1800000"
#LINUXKERNEL="https://github.com/cubieboard/CC-A80-kernel-source"
#LINUXSOURCE="linux-sunxi-a80"
#LINUXCONFIG="linux-sunxi-a80.config"
;;
#--------------------------------------------------------------------------------------------------------------------------------


aw-som-a20)#enabled
#description A20 dual core SoM
#build 0
#--------------------------------------------------------------------------------------------------------------------------------
# https://aw-som.com/
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="1.1"
BOOTCONFIG="Awsom_defconfig" 
MODULES="hci_uart gpio_sunxi bt_gpio wifi_gpio rfcomm hidp bonding spi_sun7i"
MODULES_NEXT=""
;;


cubieboard)#enabled
#description A10 single core 1Gb SoC
#build 2
#--------------------------------------------------------------------------------------------------------------------------------
# Cubieboard
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="4.2"
BOOTCONFIG="Cubieboard_config" 
MODULES="hci_uart gpio_sunxi bt_gpio wifi_gpio rfcomm hidp sunxi-ir bonding spi_sun7i"
MODULES_NEXT=""
;;


cubieboard2)#enabled
#description A20 dual core 1Gb SoC
#build 3
#--------------------------------------------------------------------------------------------------------------------------------
# Cubieboard
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="4.2"
BOOTCONFIG="Cubieboard2_config" 
MODULES="hci_uart gpio_sunxi bt_gpio wifi_gpio rfcomm hidp sunxi-ir bonding spi_sun7i"
MODULES_NEXT=""
;;


cubietruck)#enabled
#description A20 dual core 2Gb SoC Wifi
#build 3
#--------------------------------------------------------------------------------------------------------------------------------
# Cubieboard
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="4.2"
BOOTCONFIG="Cubietruck_config" 
MODULES="hci_uart gpio_sunxi bt_gpio wifi_gpio rfcomm hidp sunxi-ir bonding spi_sun7i bcmdhd"
MODULES_NEXT="brcmfmac rfcomm hidp"
;;


lime-a10)#enabled
#description A10 single core 512Mb SoC
#build 2
#--------------------------------------------------------------------------------------------------------------------------------
# Olimex Lime
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="1.1"
BOOTCONFIG="A10-OLinuXino-Lime_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i 8021q a20_tp"
MODULES_NEXT=""
;;


lime)#enabled
#description A20 dual core 512Mb SoC
#build 3
#--------------------------------------------------------------------------------------------------------------------------------
# Olimex Lime
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="2.0"
BOOTCONFIG="A20-OLinuXino-Lime_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i 8021q a20_tp"
MODULES_NEXT=""
;;


lime2)#enabled
#description A20 dual core 1Gb SoC
#build 3
#--------------------------------------------------------------------------------------------------------------------------------
# Olimex Lime 2
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="2.0"
BOOTCONFIG="A20-OLinuXino-Lime2_defconfig" 
MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i 8021q a20_tp"
MODULES_NEXT=""
;;


micro)#enabled
#description A20 dual core 1Gb SoC	
#build 3
#--------------------------------------------------------------------------------------------------------------------------------
# Olimex Lime mainline kernel	/ experimental
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="2.0"
BOOTCONFIG="A20-OLinuXino_MICRO_config"
MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i 8021q a20_tp"
MODULES_NEXT=""
;;


pcduino3nano)#enabled
#description A20 dual core 1Gb SoC
#build 3
#--------------------------------------------------------------------------------------------------------------------------------
# pcduino3nano
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="1.1"
BOOTCONFIG="Linksprite_pcDuino3_Nano_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i"
MODULES_NEXT=""
;;


bananapi)#enabled
#description A20 dual core 1Gb SoC
#build 3
#--------------------------------------------------------------------------------------------------------------------------------
# Bananapi
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="3.3"
BOOTCONFIG="Bananapi_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i 8021q a20_tp"
MODULES_NEXT="brcmfmac"
LINUXFAMILY="banana"
;;


bananapipro)#enabled
#description A20 dual core 1Gb SoC Wifi
#build 0
#--------------------------------------------------------------------------------------------------------------------------------
# Bananapi
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="3.3"
BOOTCONFIG="Bananapro_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i 8021q a20_tp"
MODULES_NEXT="brcmfmac"
LINUXFAMILY="banana"
;;


lamobo-r1)#enabled
#description A20 dual core 1Gb SoC Switch
#build 3
#--------------------------------------------------------------------------------------------------------------------------------
# Bananapi
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="3.3"
BOOTCONFIG="Lamobo_R1_defconfig"
# temporally
UBOOTTAG="v2015.04"
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i 8021q"
MODULES_NEXT="brcmfmac"
LINUXFAMILY="banana"
;;


orangepi)#enabled
#description A20 dual core 1Gb SoC Wifi USB hub
#build 3
#--------------------------------------------------------------------------------------------------------------------------------
# Bananapi
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="1.5"
BOOTCONFIG="Orangepi_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i 8021q a20_tp"
MODULES_NEXT=""
LINUXFAMILY="banana"
;;


orangepimini)#enabled
#description A20 dual core 1Gb SoC Wifi
#build 0
#--------------------------------------------------------------------------------------------------------------------------------
# Bananapi
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="1.5"
BOOTCONFIG="Orangepi_mini_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i 8021q a20_tp"
MODULES_NEXT=""
LINUXFAMILY="banana"
;;


orangepiplus)#disabled
#--------------------------------------------------------------------------------------------------------------------------------
# Bananapi
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="1.2"
BOOTCONFIG="Orangepi_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i 8021q a20_tp"
MODULES_NEXT=""
OFFSET="20" # MB (1 x 2048 = default)
BOOTSIZE="16" # Mb size of boot partition
;;


hummingbird)#disabled
#--------------------------------------------------------------------------------------------------------------------------------
# Bananapi
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="0.0"

# temporally
#UBOOTTAG="v2015.04"

BOOTCONFIG="Hummingbird_A31_config"
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i"
MODULES_NEXT=""
;;


cubox-i)#enabled
#description Freescale iMx dual/quad core Wifi
#build 1
#--------------------------------------------------------------------------------------------------------------------------------
# cubox-i & hummingboard 3.14.xx
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="3.0"
BOOTLOADER="https://github.com/SolidRun/u-boot-imx6"
BOOTDEFAULT="HEAD"
BOOTSOURCE="u-boot-cubox"
BOOTCONFIG="mx6_cubox-i_config"
CPUMIN="396000"
CPUMAX="996000"
MODULES="bonding"
MODULES_NEXT="bonding"
LINUXKERNEL="https://github.com/linux4kix/linux-linaro-stable-mx6"
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
#--------------------------------------------------------------------------------------------------------------------------------
# Udoo quad
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="2.0"
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
LINUXKERNEL="https://github.com/UDOOboard/linux_kernel"
LINUXCONFIG="linux-udoo"
LINUXSOURCE="linux-neo"
LINUXDEFAULT="imx_3.14.28_1.0.0_ga_udoo"
LINUXFAMILY="udoo"
;;


udoo-neo)#enabled
#description Freescale iMx singe core Wifi
#build 0
#--------------------------------------------------------------------------------------------------------------------------------
# Udoo Neo
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="1.2"
BOOTSIZE="32"
BOOTLOADER="https://github.com/UDOOboard/uboot-imx"
BOOTSOURCE="u-boot-neo"
BOOTCONFIG="udoo_neo_config"
CPUMIN="198000"
CPUMAX="996000"
MODULES="bonding"
MODULES_NEXT=""
LINUXKERNEL="https://github.com/UDOOboard/linux_kernel"
LINUXCONFIG="linux-udoo-neo"
LINUXSOURCE="linux-neo"
LINUXFAMILY="udoo"
;;


*) echo "Board configuration not found"
exit
;;
esac


#--------------------------------------------------------------------------------------------------------------------------------
# Vanilla Linux, second option, ...
#--------------------------------------------------------------------------------------------------------------------------------
if [[ $BRANCH == *next* ]];then
	# All next compilations are using mainline u-boot & kernel
	LINUXKERNEL="git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git"
	LINUXSOURCE="linux-mainline"
	LINUXCONFIG="linux-sunxi-next"
	LINUXDEFAULT="master"
	LINUXFAMILY="sunxi"
	FIRMWARE=""
	if [[ $BOARD == "udoo" ]];then
	LINUXKERNEL="https://github.com/patrykk/linux-udoo"
	LINUXSOURCE="linux-udoo-next"
	LINUXCONFIG="linux-udoo-next"
	LINUXDEFAULT="4.2"
	KERNELTAG=""
	LINUXFAMILY="udoo"
	fi
fi

# all boards have same revision
REVISION="4.3"
