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
# Source patching functions
#

patching_sources(){
#--------------------------------------------------------------------------------------------------------------------------------
# Patching kernel sources
#--------------------------------------------------------------------------------------------------------------------------------
echo -e "[\e[0;32m ok \x1B[0m] Patching kernel $KERNELTAG"
cd $DEST/$LINUXSOURCE

# mainline
if [[ $BRANCH == "next" && ($LINUXCONFIG == *sunxi* || $LINUXCONFIG == *cubox*) ]] ; then

	# fix kernel tag
	if [[ $KERNELTAG == "" ]] ; then
		git checkout -q master
	else
		git checkout -q $KERNELTAG
	fi
	
	# Fix BRCMFMAC AP mode for Cubietruck / Banana PRO
	if [ "$(cat drivers/net/wireless/brcm80211/brcmfmac/feature.c | grep "mbss\", 0);\*")" == "" ]; then
		sed -i 's/brcmf_feat_iovar_int_set(ifp, BRCMF_FEAT_MBSS, "mbss", 0);/\/*brcmf_feat_iovar_int_set(ifp, BRCMF_FEAT_MBSS, "mbss", 0);*\//g' drivers/net/wireless/brcm80211/brcmfmac/feature.c
	fi
	
	# install device tree blobs in separate package, link zImage to kernel image script
	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/packaging-next.patch | grep previ)" == "" ]; then
		patch -p1 < $SRC/lib/patch/packaging-next.patch
	fi

	# copy bananar1 DTS
	if [ "$(cat arch/arm/boot/dts/Makefile | grep sun7i-a20-lamobo-r1)" == "" ]; then
		sed -i 's/sun7i-a20-bananapi.dtb \\/sun7i-a20-bananapi.dtb \\\n    sun7i-a20-lamobo-r1.dtb \\/g' arch/arm/boot/dts/Makefile
		cp $SRC/lib/patch/sun7i-a20-lamobo-r1.dts arch/arm/boot/dts/
	fi
	
	# copy orange pi DTS
	if [ "$(cat arch/arm/boot/dts/Makefile | grep sun7i-a20-orangepi)" == "" ]; then
		sed -i 's/sun7i-a20-bananapi.dtb \\/sun7i-a20-bananapi.dtb \\\n    sun7i-a20-orangepi.dtb \\/g' arch/arm/boot/dts/Makefile
		cp $SRC/lib/patch/sun7i-a20-orangepi.dts arch/arm/boot/dts/
		cp $SRC/lib/patch/sun4i-a10.h arch/arm/boot/dts/include/dt-bindings/pinctrl
	fi

    # copy pcduino nano DTS
	if [ "$(cat arch/arm/boot/dts/Makefile | grep sun7i-a20-pcduino3-nano)" == "" ]; then
		sed -i 's/sun7i-a20-bananapi.dtb \\/sun7i-a20-bananapi.dtb \\\n    sun7i-a20-pcduino3-nano.dtb \\/g' arch/arm/boot/dts/Makefile
		cp $SRC/lib/patch/sun7i-a20-pcduino3-nano.dts arch/arm/boot/dts/
	fi
	
	# add r1 switch driver
	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/bananapi-r1-4.x.patch | grep previ)" == "" ]; then
		rm -rf drivers/net/phy/b53/
		rm -f drivers/net/phy/swconfig.c
		rm -f drivers/net/phy/swconfig_leds.c
		rm -f include/linux/platform_data/b53.h
		rm -f include/linux/switch.h
		rm -f include/uapi/linux/switch.h 
		patch -p1 -f -s -m < $SRC/lib/patch/bananapi-r1-4.x.patch
	fi
fi

if [[ $BRANCH == "next" && $BOARD == "udoo" ]] ; then
	# hard fixed DTS tree
	cp $SRC/lib/patch/Makefile-udoo-only arch/arm/boot/dts/Makefile
	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/packaging-udoo.patch | grep previ)" == "" ]; then
		patch -p1 < $SRC/lib/patch/packaging-udoo.patch
	fi
fi

# sunxi 3.4
if [[ $LINUXSOURCE == "linux-sunxi" ]] ; then
	# if the source is already patched for banana, do reverse GMAC patch
	if [ "$(cat arch/arm/kernel/setup.c | grep BANANAPI)" != "" ]; then
		echo "Reversing Banana patch"
		patch --batch -t -p1 < $SRC/lib/patch/bananagmac.patch
	fi
	# SPI functionality
    	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/spi.patch | grep previ)" == "" ]; then
		patch --batch -f -p1 < $SRC/lib/patch/spi.patch
    	fi
	# banana/orange gmac  
	if [[ $BOARD == banana* || $BOARD == orangepi* || $BOARD == lamobo* ]] ; then
		if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/bananagmac.patch | grep previ)" == "" ]; then
			patch --batch -N -p1 < $SRC/lib/patch/bananagmac.patch
		fi
	fi
	# compile sunxi tools
	compile_sunxi_tools
fi

# cubox / hummingboard 3.14
if [[ $LINUXSOURCE == "linux-cubox" ]] ; then
	# SPI and I2C functionality
	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/hb-i2c-spi.patch | grep previ)" == "" ]; then
		patch -p1 < $SRC/lib/patch/hb-i2c-spi.patch
	fi
	# deb packaging patch
	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/packaging-cubox.patch | grep previ)" == "" ]; then
		patch --batch -f -p1 < $SRC/lib/patch/packaging-cubox.patch
	fi	
fi

# compiler reverse patch. It has already been fixed.
if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/compiler.patch | grep Reversed)" != "" ]; then
	patch --batch -t -p1 < $SRC/lib/patch/compiler.patch
fi

# u-boot
cd $DEST/$BOOTSOURCE
echo -e "[\e[0;32m ok \x1B[0m] Patching U-boot $UBOOTTAG"
# fix kernel tag
	if [[ $UBOOTTAG == "" ]] ; then
		git checkout -q master
	else
		git checkout -q -f $UBOOTTAG
	fi

if [[ $BOARD == "udoo" ]] ; then
	# This enabled boot script loading from ext2 partition which is my default setup
	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/udoo-uboot-fatboot.patch | grep previ)" == "" ]; then
       		patch --batch -N -p1 < $SRC/lib/patch/udoo-uboot-fatboot.patch
	fi
fi
if [[ $BOARD == "udoo-neo" ]] ; then
	# This enables loading boot.scr from / and /boot, fat and ext2
	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/udoo-neo_fat_and_ext_boot_script_load.patch | grep previ)" == "" ]; then
       		patch --batch -N -p1 < $SRC/lib/patch/udoo-neo_fat_and_ext_boot_script_load.patch
	fi
fi
if [[ $LINUXCONFIG == *sunxi* ]] ; then
	# Add router R1 to uboot
	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/add-lamobo-r1-uboot.patch | grep create)" == "" ]; then
		patch --batch -N -p1 < $SRC/lib/patch/add-lamobo-r1-uboot.patch
	fi
	# Add awsom to uboot
	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/add-awsom-uboot.patch | grep create)" == "" ]; then
		patch --batch -N -p1 < $SRC/lib/patch/add-awsom-uboot.patch
	fi
	# Add boot splash to uboot
	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/sunxi-boot-splash.patch | grep create)" == "" ]; then
		patch --batch -N -p1 < $SRC/lib/patch/sunxi-boot-splash.patch
	fi
fi
}