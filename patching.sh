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



# description, patch, direction-normal or reverse, section
patchme ()
{
if [ $3 == "reverse" ]; then
	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/$4/$2 | grep Reversed)" != "" ]; then 
		display_alert "... $1" "$4" "info"
		patch --batch --silent -t -p1 < $SRC/lib/patch/$4/$2 > /dev/null 2>&1
	else
		display_alert "... $1 *** back to defaults *** " "$4" "wrn"
	fi
else
	if [ "$(patch --batch -p1 -N < $SRC/lib/patch/$4/$2 | grep Skipping)" != "" ]; then 
		display_alert "... $1 already applied" "$4" "wrn"
	else
		display_alert "... $1" "$4" "info"
	fi
fi
}

addnewdevice()
{
if [ $3 == "kernel" ]; then
	if [ "$(cat arch/arm/boot/dts/Makefile | grep $2)" == "" ]; then
		display_alert "... adding $1" "kernel" "info"
		sed -i 's/sun7i-a20-bananapi.dtb \\/sun7i-a20-bananapi.dtb \\\n    '$2'.dtb \\/g' arch/arm/boot/dts/Makefile
		cp $SRC/lib/patch/devices/$2".dts" arch/arm/boot/dts/
	fi
else
	# add to uboot to , experimental
	if [ "$(cat $SOURCES/$BOOTSOURCE/arch/arm/dts/Makefile | grep $2)" == "" ]; then
		display_alert "... adding $1 to u-boot DTS" "kernel" "info"
		sed -i 's/sun7i-a20-bananapi.dtb \\/sun7i-a20-bananapi.dtb \\\n    '$2'.dtb \\/g' arch/arm/dts/Makefile
		cp $SRC/lib/patch/devices/$2".dts" $SOURCES/$BOOTSOURCE/arch/arm/dts
	fi
fi
}

patching_sources(){
#--------------------------------------------------------------------------------------------------------------------------------
# Patching kernel sources
#--------------------------------------------------------------------------------------------------------------------------------
cd $SOURCES/$BOOTSOURCE

# fix u-boot tag
if [[ $UBOOTTAG == "" ]] ; then
	git checkout $FORCE -q $BOOTDEFAULT
	else
	git checkout $FORCE -q $UBOOTTAG
fi

cd $SOURCES/$LINUXSOURCE


if [[ $KERNELTAG == "" ]] ; then KERNELTAG="$LINUXDEFAULT"; fi
# fix kernel tag
if [[ $BRANCH == "next" ]] ; then
		git checkout $FORCE -q $KERNELTAG
	else
		git checkout $FORCE -q $LINUXDEFAULT

fi

# What are we building
grab_kernel_version

display_alert "Patching" "kernel $VER" "info"

# this is for almost all sources
patchme "compiler bug" 					"compiler.patch" 				"reverse" "kernel"


# mainline
if [[ $BRANCH == "next" && ($LINUXCONFIG == *sunxi* || $LINUXCONFIG == *cubox*) ]] ; then


	


	patchme "fix BRCMFMAC AP mode Banana & CT" 					"brcmfmac_ap_banana_ct.patch" 		"default" "kernel"
	patchme "deb packaging fix" 								"packaging-next.patch" 				"default" "kernel"
	patchme "Banana M2 support, LEDs" 							"Sinoviop-bananas-M2-R1-M1-fixes.patch" 	"default" "kernel"	
	
	#patchme "Security System #0001" 	"0001-ARM-sun5i-dt-Add-Security-System-to-A10s-SoC-DTS.patch" "default" "kernel"
	#patchme "Security System #0002" 	"0002-ARM-sun6i-dt-Add-Security-System-to-A31-SoC-DTS.patch" "default" "kernel"
	#patchme "Security System #0003" 	"0003-ARM-sun4i-dt-Add-Security-System-to-A10-SoC-DTS.patch" "default" "kernel"
	#patchme "Security System #0004" 	"0004-ARM-sun7i-dt-Add-Security-System-to-A20-SoC-DTS.patch" "default" "kernel"
	#rm Documentation/devicetree/bindings/crypto/sun4i-ss.txt
	#patchme "Security System #0005" 	"0005-ARM-sun4i-dt-Add-DT-bindings-documentation-for-SUN4I.patch" "default" "kernel"
	#rm -r drivers/crypto/sunxi-ss/
	#patchme "Security System #0006" 	"0006-crypto-Add-Allwinner-Security-System-crypto-accelera.patch" "default" "kernel"
	#patchme "Security System #0007" 	"0007-MAINTAINERS-Add-myself-as-maintainer-of-Allwinner-Se.patch" "default" "kernel"
	#patchme "Security System #0008" 	"0008-crypto-sun4i-ss-support-the-Security-System-PRNG.patch" "default" "kernel"
	#patchme "Security System #0009 remove failed A31" 	"0009-a31_breaks.patch" "default" "kernel"
		
	# add r1 switch driver
	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/kernel/bananapi-r1-4.x.patch | grep previ)" == "" ]; then
		rm -rf drivers/net/phy/b53/
		rm -f drivers/net/phy/swconfig.c
		rm -f drivers/net/phy/swconfig_leds.c
		rm -f include/linux/platform_data/b53.h
		rm -f include/linux/switch.h
		rm -f include/uapi/linux/switch.h 
		patch -p1 -f -s -m < $SRC/lib/patch/kernel/bananapi-r1-4.x.patch
	fi

	# Add new devices
	addnewdevice "Lamobo R1" 			"sun7i-a20-lamobo-r1"					"kernel"
	#addnewdevice "Orange PI" 			"sun7i-a20-orangepi"					"kernel"
	#addnewdevice "Orange PI mini" 		"sun7i-a20-orangepi-mini"				"kernel"
	#addnewdevice "PCDuino Nano3" 		"sun7i-a20-pcduino3-nano"				"kernel"
	addnewdevice "Bananapi M2 A31s" 	"sun6i-a31s-bananapi-m2"				"kernel"
	addnewdevice "Bananapi M1 Plus" 	"sun7i-a20-bananapi-m1-plus"			"kernel"
	addnewdevice "Bananapi R1" 			"sun7i-a20-bananapi-r1"					"kernel"
	
fi

if [[ $BOARD == udoo* ]] ; then
	# hard fixed DTS tree
	if [[ $BRANCH == "next" ]] ; then
		cp $SRC/lib/patch/misc/Makefile-udoo-only arch/arm/boot/dts/Makefile
		patchme "Install DTB in dedicated package" 				"packaging-next.patch" 			"default" "kernel"
		patchme "Upgrade to 4.2.1" 								"patch-4.2.1" 			"default" "kernel"
		patchme "Upgrade to 4.2.2" 								"patch-4.2.1-2" 			"default" "kernel"
	else
	# 
	patchme "remove strange DTBs from tree" 					"udoo_dtb.patch" 				"default" "kernel"
	patchme "remove n/a v4l2-capture from Udoo DTS" 			"udoo_dts_fix.patch" 			"default" "kernel"
	# patchme "deb packaging fix" 								"packaging-udoo-fix.patch" 		"default" "kernel"
	# temp instead of this patch
	cp $SRC/lib/patch/kernel/builddeb-fixed-udoo scripts/package/builddeb
	fi
fi

# sunxi 3.4
if [[ $LINUXSOURCE == "linux-sunxi" ]] ; then
	patchme "SPI functionality" 					"spi.patch" 								"default" "kernel"
	patchme "Debian packaging fix" 					"packaging-sunxi-fix.patch" 				"default" "kernel"
	patchme "Aufs3" 								"linux-sunxi-3.4.108-overlayfs.patch" 		"default" "kernel"
	patchme "More I2S and Spdif" 					"i2s_spdif_sunxi.patch" 					"default" "kernel"
	patchme "A fix for rt8192" 						"rt8192cu-missing-case.patch" 				"default" "kernel"
	patchme "Upgrade to 3.4.109" 					"patch-3.4.108-109" 						"default" "kernel"
	
	
	# banana/orange gmac  
	if [[ $BOARD == banana* || $BOARD == orangepi* || $BOARD == lamobo* ]] ; then
		patchme "Bananapi/Orange/R1 gmac" 								"bananagmac.patch" 		"default" "kernel"
		patchme "Bananapi PRO wireless" 								"wireless-bananapro.patch" 		"default" "kernel"
	else
		patchme "Banana PI/ PRO / Orange / R1 gmac" 					"bananagmac.patch" 		"reverse" "kernel"
		patchme "Bananapi PRO wireless" 								"wireless-bananapro.patch" 		"reverse" "kernel"
	fi
fi

# cubox / hummingboard 3.14
if [[ $LINUXSOURCE == linux-cubox* ]] ; then
	patchme "SPI and I2C functionality" 						"hb-i2c-spi.patch" 				"default" "kernel"
	patchme "deb packaging fix" 								"packaging-cubox.patch" 				"default" "kernel"
	# Upgrade to 3.14.53
	for (( c=14; c<=52; c++ ))
	do
		display_alert "Patching" "3.14.$c-$(( $c+1 ))" "info"
		wget wget -qO - "https://www.kernel.org/pub/linux/kernel/v3.x/incr/patch-3.14.$c-$(( $c+1 )).gz" | gzip -d | patch -p1 -l -f -s >/dev/null 2>&1     
	done
	
fi


#--------------------------------------------------------------------------------------------------------------------------------
# Patching u-boot sources
#--------------------------------------------------------------------------------------------------------------------------------

cd $SOURCES/$BOOTSOURCE
display_alert "Patching" "u-boot $UBOOTTAG" "info"

if [[ $BOARD == "udoo" ]] ; then
	#patchme "Enabled Udoo boot script loading from ext2" 					"udoo-uboot-fatboot.patch" 		"default" "u-boot"
	# temp instead of this patch
	cp $SRC/lib/patch/u-boot/udoo.h include/configs/
fi

if [[ $BOARD == "udoo-neo" ]] ; then
	# This enables loading boot.scr from / and /boot, fat and ext2
	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/udoo-neo_fat_and_ext_boot_script_load.patch | grep previ)" == "" ]; then
       		patch --batch -N -p1 < $SRC/lib/patch/udoo-neo_fat_and_ext_boot_script_load.patch
	fi
fi
if [[ $LINUXCONFIG == *sunxi* ]] ; then
	rm -f configs/Lamobo_R1_defconfig configs/Awsom_defconfig
	patchme "Add Lamobo R1" 					"add-lamobo-r1-uboot.patch" 		"default" "u-boot"
	patchme "Add AW SOM" 						"add-awsom-uboot.patch" 			"default" "u-boot"
	patchme "Add boot splash" 					"sunxi-boot-splash.patch" 			"default" "u-boot"
	
	# Add new devices
	addnewdevice "Lamobo R1" 			"sun7i-a20-lamobo-r1"	"u-boot"
	
fi



#--------------------------------------------------------------------------------------------------------------------------------
# Patching other sources: FBTFT drivers, ...
#--------------------------------------------------------------------------------------------------------------------------------
cd $SOURCES/$MISC4_DIR
display_alert "Patching" "other sources" "info"


# add small TFT display support  
if [[ "$FBTFT" = "yes" && $BRANCH != "next" ]]; then
IFS='.' read -a array <<< "$VER"
cd $SOURCES/$MISC4_DIR
if (( "${array[0]}" == "3" )) && (( "${array[1]}" < "5" ))
then
echo "star kernel"
	git checkout $FORCE -q 06f0bba152c036455ae76d26e612ff0e70a83a82
else
	git checkout $FORCE -q master
fi

if [[ $BOARD == banana* || $BOARD == orangepi* || $BOARD == lamobo* ]] ; then
patchme "DMA disable on FBTFT drivers" 					"bananafbtft.patch" 		"default" "misc"


else
patchme "DMA disable on FBTFT drivers" 					"bananafbtft.patch" 		"reverse" "misc"
fi

mkdir -p $SOURCES/$LINUXSOURCE/drivers/video/fbtft
mount --bind $SOURCES/$MISC4_DIR $SOURCES/$LINUXSOURCE/drivers/video/fbtft
cd $SOURCES/$LINUXSOURCE
patchme "small TFT display support" 					"small_lcd_drivers.patch" 		"default" "kernel"
else
patchme "small TFT display support" 					"small_lcd_drivers.patch" 		"reverse" "kernel"
umount $SOURCES/$LINUXSOURCE/drivers/video/fbtft >/dev/null 2>&1
fi


}
