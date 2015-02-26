#!/bin/bash
#
# Copyright (c) 2014 Igor Pecovnik, igor.pecovnik@gma**.com
#
# www.igorpecovnik.com / images + support
#
# Board definitions
#

SDSIZE="1200"                               # SD image size in MB

#--------------------------------------------------------------------------------------------------------------------------------
# common for default allwinner kernel-source
#--------------------------------------------------------------------------------------------------------------------------------


BOOTLOADER="https://github.com/RobertCNelson/u-boot"
BOOTSOURCE="u-boot"
LINUXKERNEL="https://github.com/dan-and/linux-sunxi"
LINUXSOURCE="linux-sunxi"
LINUXCONFIG="linux-sunxi"
CPUMIN="480000"
CPUMAX="1010000"
DOCS=""
DOCSDIR=""
FIRMWARE="bin/ap6210.zip"
MISC1="https://github.com/linux-sunxi/sunxi-tools.git"		
MISC1_DIR="sunxi-tools"
MISC2=""	
MISC2_DIR=""						
MISC3="https://github.com/dz0ny/rt8192cu"	
MISC3_DIR="rt8192cu"
# MISC4 = RESERVED
# MISC4_DIR = RESERVED

#--------------------------------------------------------------------------------------------------------------------------------
# common for default allwinner kernel-source 
#--------------------------------------------------------------------------------------------------------------------------------


if [[ $BRANCH == *next* ]];then
	# All next compilations are using mainline u-boot & kernel
	LINUXKERNEL="git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git"
	LINUXSOURCE="linux-mainline"
	LINUXCONFIG="linux-sunxi-next"
	FIRMWARE=""
	if [[ $BOARD == "udoo" ]];then
	LINUXKERNEL="https://github.com/patrykk/linux-udoo"
	LINUXSOURCE="linux-udoo-next"
	LINUXCONFIG="linux-udoo-next"
	fi
fi

#--------------------------------------------------------------------------------------------------------------------------------
# choose configuration
#--------------------------------------------------------------------------------------------------------------------------------
case $BOARD in


cubieboard4)
#--------------------------------------------------------------------------------------------------------------------------------
# Cubieboards 3.4.x
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="0.0"
BOOTCONFIG="cubietruck"
CPUMIN="1200000"
CPUMAX="1800000"
LINUXKERNEL="https://github.com/cubieboard/CC-A80-kernel-source"
LINUXSOURCE="linux-sunxi-a80"
LINUXCONFIG="linux-sunxi-a80.config"
FIRMWARE=""
DTBS=""
MISC1=""	
MISC1_DIR=""
;;
#--------------------------------------------------------------------------------------------------------------------------------


cubieboard)
#--------------------------------------------------------------------------------------------------------------------------------
# Cubieboard
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="3.3"
BOOTCONFIG="Cubieboard_config" 
MODULES="hci_uart gpio_sunxi bt_gpio wifi_gpio rfcomm hidp sunxi-ir bonding spi_sun7i"
;;


cubieboard2)
#--------------------------------------------------------------------------------------------------------------------------------
# Cubieboard
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="3.3"
BOOTCONFIG="Cubieboard2_config" 
MODULES="hci_uart gpio_sunxi bt_gpio wifi_gpio rfcomm hidp sunxi-ir bonding spi_sun7i"
;;


cubietruck)
#--------------------------------------------------------------------------------------------------------------------------------
# Cubieboard
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="3.3"
BOOTCONFIG="Cubietruck_config" 
MODULES="hci_uart gpio_sunxi bt_gpio wifi_gpio rfcomm hidp sunxi-ir bonding spi_sun7i bcmdhd"
;;


lime)
#--------------------------------------------------------------------------------------------------------------------------------
# Olimex Lime
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="1.6"
BOOTCONFIG="A20-OLinuXino-Lime_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i"
;;


lime2)
#--------------------------------------------------------------------------------------------------------------------------------
# Olimex Lime 2
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="1.6"
BOOTCONFIG="A20-OLinuXino-Lime2_defconfig" 
MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i"
;;


micro)
#--------------------------------------------------------------------------------------------------------------------------------
# Olimex Lime mainline kernel	/ experimental
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="1.5"
BOOTCONFIG="A20-OLinuXino_MICRO_config"
MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i"
;;


pcduino3)
#--------------------------------------------------------------------------------------------------------------------------------
# pcduino3
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="0.0"
BOOTCONFIG="Linksprite_pcDuino3_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i"
;;


bananapi)
#--------------------------------------------------------------------------------------------------------------------------------
# Bananapi
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="2.2"
BOOTCONFIG="Bananapi_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i"
;;


bananapipro)
#--------------------------------------------------------------------------------------------------------------------------------
# BananapiPRO
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="2.3"
BOOTCONFIG="Bananapi_defconfig"
LINUXCONFIG="linux-sunxi-bpipro-next"
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i"
;;


orangepi)
#--------------------------------------------------------------------------------------------------------------------------------
# Orangepi
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="1.1"
BOOTCONFIG="Bananapi_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i"
;;


hummingbird)
#--------------------------------------------------------------------------------------------------------------------------------
# Hummingbird
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="0.0"
BOOTCONFIG="Hummingbird_A31_config"
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i"
;;


cubox-i)
#--------------------------------------------------------------------------------------------------------------------------------
# cubox-i & hummingboard 3.14.xx
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="2.6"
BOOTLOADER="https://github.com/SolidRun/u-boot-imx6"
BOOTSOURCE="u-boot-cubox"
BOOTCONFIG="mx6_cubox-i_config"
CPUMIN="792000"
CPUMAX="996000"
MODULES="bonding"
LINUXKERNEL="https://github.com/linux4kix/linux-linaro-stable-mx6"
LINUXCONFIG="linux-cubox"
LINUXSOURCE="linux-cubox"
LOCALVERSION="-cubox"
DTBS="imx6q-cubox-i.dtb imx6dl-cubox-i.dtb imx6dl-hummingboard.dtb imx6q-hummingboard.dtb"
;;


udoo)
#--------------------------------------------------------------------------------------------------------------------------------
# Udoo quad
#--------------------------------------------------------------------------------------------------------------------------------
REVISION="1.0"
BOOTCONFIG="udoo_quad_config"
CPUMIN="792000"
CPUMAX="996000"
MODULES="bonding"
;;


*) echo "Board configuration not found"
exit
;;
esac


# Common part 2 
# It must be here
MISC4="https://github.com/notro/fbtft"
MISC4_DIR="$LINUXSOURCE/drivers/video/fbtft"
