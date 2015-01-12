#!/bin/bash
#
# Copyright (c) 2014 Igor Pecovnik, igor.pecovnik@gma**.com
#
# www.igorpecovnik.com / images + support
#
# Board definitions
#


# we need temp variable 
CHOOSEBOARD=$BOARD


#--------------------------------------------------------------------------------------------------------------------------------
# common for default allwinner kernel-source
#--------------------------------------------------------------------------------------------------------------------------------


BOOTLOADER="https://github.com/linux-sunxi/u-boot-sunxi"
BOOTSOURCE="u-boot-sunxi"
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
	BOOTLOADER="https://github.com/RobertCNelson/u-boot"
	BOOTSOURCE="u-boot"
	LINUXKERNEL="git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git"
	LINUXSOURCE="linux-mainline"
	LINUXCONFIG="linux-sunxi-next"
	FIRMWARE=""
	CHOOSEBOARD=$BOARD"-"$BRANCH
fi

#--------------------------------------------------------------------------------------------------------------------------------
# choose configuration
#--------------------------------------------------------------------------------------------------------------------------------
case $CHOOSEBOARD in


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


cubieboard2 | cubietruck)
#--------------------------------------------------------------------------------------------------------------------------------
# Cubieboards 3.4.x (Thoose boards share the same image)
#--------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="Cubietruck_config"
MODULES="hci_uart gpio_sunxi bt_gpio wifi_gpio rfcomm hidp sunxi-ir bonding spi_sun7i bcmdhd"
;;
#--------------------------------------------------------------------------------------------------------------------------------


cubieboard)
#--------------------------------------------------------------------------------------------------------------------------------
# Cubieboard 3.4.x
#--------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="Cubieboard_config"
MODULES="hci_uart gpio_sunxi bt_gpio wifi_gpio rfcomm hidp sunxi-ir bonding spi_sun7i"
;;
#--------------------------------------------------------------------------------------------------------------------------------


cubieboard-next)
#--------------------------------------------------------------------------------------------------------------------------------
# Cubieboard mainline kernel	/ experimental
#--------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="Cubieboard_defconfig" 
MODULES="bonding"
;;


cubieboard2-next)
#--------------------------------------------------------------------------------------------------------------------------------
# Cubieboard mainline kernel	/ experimental
#--------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="Cubieboard2_defconfig" 
MODULES="bonding"
;;


cubietruck-next)
#--------------------------------------------------------------------------------------------------------------------------------
# Cubieboard mainline kernel	/ experimental
#--------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="Cubietruck_defconfig" 
MODULES="bonding"
;;


lime) 
#--------------------------------------------------------------------------------------------------------------------------------
# Olimex Lime 512Mb 3.4.x
#--------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="A20-OLinuXino-Lime_config"
MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i"
;;


lime-next)
#--------------------------------------------------------------------------------------------------------------------------------
# Olimex Lime mainline kernel	/ experimental
#--------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="A20-OLinuXino-Lime_defconfig"
MODULES="bonding"
;;


micro) 
#--------------------------------------------------------------------------------------------------------------------------------
# Olimex Micro 3.4.x
#--------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="A20-OLinuXino-Micro_config"
MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i"
;;

micro-next)
#--------------------------------------------------------------------------------------------------------------------------------
# Olimex Lime mainline kernel	/ experimental
#--------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="A20-OLinuXino_MICRO_config"
MODULES="bonding"
;;


lime2) 
#--------------------------------------------------------------------------------------------------------------------------------
# Olimex Lime2 1024Mb 3.4.x
#--------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="A20-OLinuXino_Lime2_config"
MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i"
;;


lime2-next)
#--------------------------------------------------------------------------------------------------------------------------------
# Olimex Lime mainline kernel	/ experimental
#--------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="A20-OLinuXino-Lime2_defconfig" 
MODULES="bonding"
;;


pcduino3-next)
#--------------------------------------------------------------------------------------------------------------------------------
# pcduino3 mainline kernel / experimental
#--------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="Linksprite_pcDuino3_defconfig"
MODULES="bonding"
;;


bananapi-next)
#--------------------------------------------------------------------------------------------------------------------------------
# bananapi mainline kernel / experimental
#--------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="Bananapi_defconfig"
MODULES="bonding"
;;


bananapi) 
#--------------------------------------------------------------------------------------------------------------------------------
# Bananapi cubieboard based 3.4.x
#--------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="Bananapi_config"
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


cubox-i-next)
#--------------------------------------------------------------------------------------------------------------------------------
# cubox-i & hummingboard mainline
#--------------------------------------------------------------------------------------------------------------------------------
BOOTLOADER="https://github.com/SolidRun/u-boot-imx6"
BOOTSOURCE="u-boot-cubox"
BOOTCONFIG="mx6_cubox-i_config"
CPUMIN="792000"
CPUMAX="996000"
LINUXKERNEL="git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git"
LINUXSOURCE="linux-mainline"
LINUXCONFIG="linux-cubox-next"
LOCALVERSION="-mainline"
DTBS="imx6q-cubox-i.dtb imx6dl-cubox-i.dtb imx6dl-hummingboard.dtb imx6q-hummingboard.dtb"
;;


*) echo "Board configuration not found"
exit
;;
esac


# Common part 2 
# It must be here
MISC4="https://github.com/notro/fbtft"
MISC4_DIR="$LINUXSOURCE/drivers/video/fbtft"