#!/bin/bash
#
# Copyright (c) 2014 Igor Pecovnik, igor.pecovnik@gma**.com
#
# www.igorpecovnik.com / images + support
#
# Board definitions
#


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
fi

#--------------------------------------------------------------------------------------------------------------------------------
# choose configuration
#--------------------------------------------------------------------------------------------------------------------------------
case $BOARD in


cubieboard4)
#--------------------------------------------------------------------------------------------------------------------------------
# Cubieboards 3.4.x
#--------------------------------------------------------------------------------------------------------------------------------
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
BOOTLOADER="https://github.com/linux-sunxi/u-boot-sunxi"
BOOTSOURCE="u-boot-sunxi"
BOOTCONFIG="Cubieboard_config" 
MODULES="hci_uart gpio_sunxi bt_gpio wifi_gpio rfcomm hidp sunxi-ir bonding spi_sun7i"
;;


cubieboard2)
#--------------------------------------------------------------------------------------------------------------------------------
# Cubieboard
#--------------------------------------------------------------------------------------------------------------------------------
BOOTLOADER="https://github.com/linux-sunxi/u-boot-sunxi"
BOOTSOURCE="u-boot-sunxi"
BOOTCONFIG="Cubieboard2_config" 
MODULES="hci_uart gpio_sunxi bt_gpio wifi_gpio rfcomm hidp sunxi-ir bonding spi_sun7i"
;;


cubietruck)
#--------------------------------------------------------------------------------------------------------------------------------
# Cubieboard
#--------------------------------------------------------------------------------------------------------------------------------
BOOTLOADER="https://github.com/linux-sunxi/u-boot-sunxi"
BOOTSOURCE="u-boot-sunxi"
BOOTCONFIG="Cubietruck_config" 
MODULES="hci_uart gpio_sunxi bt_gpio wifi_gpio rfcomm hidp sunxi-ir bonding spi_sun7i bcmdhd"
;;


lime)
#--------------------------------------------------------------------------------------------------------------------------------
# Olimex Lime
#--------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="A20-OLinuXino-Lime_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i"
;;


lime2)
#--------------------------------------------------------------------------------------------------------------------------------
# Olimex Lime 2
#--------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="A20-OLinuXino-Lime2_defconfig" 
MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i"
;;


micro)
#--------------------------------------------------------------------------------------------------------------------------------
# Olimex Lime mainline kernel	/ experimental
#--------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="A20-OLinuXino_MICRO_config"
MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i"
;;


pcduino3)
#--------------------------------------------------------------------------------------------------------------------------------
# pcduino3
#--------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="Linksprite_pcDuino3_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i"
;;


bananapi)
#--------------------------------------------------------------------------------------------------------------------------------
# Bananapi
#--------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="Bananapi_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i"
;;


cubox-i)
#--------------------------------------------------------------------------------------------------------------------------------
# cubox-i & hummingboard 3.14.xx
#--------------------------------------------------------------------------------------------------------------------------------
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
# cubox-i & hummingboard 3.14.xx
#--------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="udoo_quad_defconfig"
CPUMIN="792000"
CPUMAX="996000"
MODULES="bonding"
LINUXKERNEL="https://github.com/linux4kix/linux-linaro-stable-mx6"
LINUXCONFIG="linux-cubox"
LINUXSOURCE="linux-cubox"
LOCALVERSION="-cubox"
;;


*) echo "Board configuration not found"
exit
;;
esac


# Common part 2 
# It must be here
MISC4="https://github.com/notro/fbtft"
MISC4_DIR="$LINUXSOURCE/drivers/video/fbtft"