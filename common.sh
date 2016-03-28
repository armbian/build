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

# Functions:
# compile_uboot
# compile_sunxi_tools
# compile_kernel
# install_external_applications
# write_uboot
# customize_image

compile_uboot (){
#---------------------------------------------------------------------------------------------------------------------------------
# Compile uboot from sources
#---------------------------------------------------------------------------------------------------------------------------------
	if [[ ! -d "$SOURCES/$BOOTSOURCEDIR" ]]; then
		exit_with_error "Error building u-boot: source directory does not exist" "$BOOTSOURCEDIR"
	fi

	display_alert "Compiling uboot. Please wait." "$VER" "info"
	echo `date +"%d.%m.%Y %H:%M:%S"` $SOURCES/$BOOTSOURCEDIR/$BOOTCONFIG >> $DEST/debug/install.log
	cd $SOURCES/$BOOTSOURCEDIR
	make -s ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE clean >/dev/null 2>&1

	# there are two methods of compilation
	if [[ $BOOTCONFIG == *config* ]]; then

		# workarounds
		local cthreads=$CTHREADS
		[[ $LINUXFAMILY == "marvell" ]] && local MAKEPARA="u-boot.mmc"
		[[ $BOARD == "odroidc2" ]] && local MAKEPARA="ARCH=arm" && local cthreads=""
	
		make $CTHREADS $BOOTCONFIG CROSS_COMPILE=$CROSS_COMPILE >/dev/null 2>&1
		[ -f .config ] && sed -i 's/CONFIG_LOCALVERSION=""/CONFIG_LOCALVERSION="-armbian"/g' .config
		[ -f .config ] && sed -i 's/CONFIG_LOCALVERSION_AUTO=.*/# CONFIG_LOCALVERSION_AUTO is not set/g' .config
		[ -f $SOURCES/$BOOTSOURCEDIR/tools/logos/udoo.bmp ] && cp $SRC/lib/bin/armbian-u-boot.bmp $SOURCES/$BOOTSOURCEDIR/tools/logos/udoo.bmp
		touch .scmversion	
		
		# patch mainline uboot configuration to boot with old kernels
		if [[ $BRANCH == "default" && $LINUXFAMILY == sun*i ]] ; then
			if [ "$(cat $SOURCES/$BOOTSOURCEDIR/.config | grep CONFIG_ARMV7_BOOT_SEC_DEFAULT=y)" == "" ]; then
				echo "CONFIG_ARMV7_BOOT_SEC_DEFAULT=y" >> $SOURCES/$BOOTSOURCEDIR/.config
				echo "CONFIG_OLD_SUNXI_KERNEL_COMPAT=y" >> $SOURCES/$BOOTSOURCEDIR/.config
			fi
		fi

		eval 'make $MAKEPARA $cthreads CROSS_COMPILE="$CCACHE $CROSS_COMPILE" 2>&1' \
		${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/compilation.log'} \
		${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Compiling u-boot..." $TTY_Y $TTY_X'} \
		${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
	else
		eval 'make $MAKEPARA $cthreads $BOOTCONFIG CROSS_COMPILE="$CCACHE $CROSS_COMPILE" 2>&1' \
		${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/compilation.log'} \
		${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Compiling u-boot..." $TTY_Y $TTY_X'} \
		${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
	fi


	# create .deb package

	local uboot_name=${CHOSEN_UBOOT}_${REVISION}_${ARCH}

	mkdir -p $DEST/debs/$uboot_name/usr/lib/$uboot_name $DEST/debs/$uboot_name/DEBIAN

# set up post install script
cat <<END > $DEST/debs/$uboot_name/DEBIAN/postinst
#!/bin/bash
set -e
if [[ \$DEVICE == "/dev/null" ]]; then exit 0; fi
if [[ \$DEVICE == "" ]]; then DEVICE="/dev/mmcblk0"; fi
if [[ \$DPKG_MAINTSCRIPT_PACKAGE == *cubox* ]] ; then
	( dd if=/usr/lib/$uboot_name/SPL of=\$DEVICE bs=512 seek=2 status=noxfer ) > /dev/null 2>&1
	( dd if=/usr/lib/$uboot_name/u-boot.img of=\$DEVICE bs=1K seek=42 status=noxfer ) > /dev/null 2>&1
elif [[ \$DPKG_MAINTSCRIPT_PACKAGE == *guitar* ]] ; then
	( dd if=/usr/lib/$uboot_name/bootloader.bin of=\$DEVICE bs=512 seek=4097 conv=fsync ) > /dev/null 2>&1
	( dd if=/usr/lib/$uboot_name/u-boot-dtb.bin of=\$DEVICE bs=512 seek=6144 conv=fsync ) > /dev/null 2>&1
elif [[ \$DPKG_MAINTSCRIPT_PACKAGE == *odroidxu4* ]] ; then
	( dd if=/usr/lib/$uboot_name/bl1.bin.hardkernel of=\$DEVICE seek=1 conv=fsync ) > /dev/null 2>&1
	( dd if=/usr/lib/$uboot_name/bl2.bin.hardkernel of=\$DEVICE seek=31 conv=fsync ) > /dev/null 2>&1
	( dd if=/usr/lib/$uboot_name/u-boot.bin of=\$DEVICE bs=512 seek=63 conv=fsync ) > /dev/null 2>&1
	( dd if=/usr/lib/$uboot_name/tzsw.bin.hardkernel of=\$DEVICE seek=719 conv=fsync ) > /dev/null 2>&1
	( dd if=/dev/zero of=\$DEVICE seek=1231 count=32 bs=512 conv=fsync ) > /dev/null 2>&1
elif [[ \$DPKG_MAINTSCRIPT_PACKAGE == *odroidc1* ]] ; then
	( dd if=/usr/lib/$uboot_name/bl1.bin.hardkernel of=\$DEVICE bs=1 count=442 conv=fsync ) > /dev/null 2>&1	
	( dd if=/usr/lib/$uboot_name/bl1.bin.hardkernel of=\$DEVICE bs=512 skip=1 seek=1 conv=fsync ) > /dev/null 2>&1	
	( dd if=/usr/lib/$uboot_name/u-boot.bin of=\$DEVICE bs=512 seek=64 conv=fsync ) > /dev/null 2>&1	
	( dd if=/dev/zero of=\$DEVICE seek=1024 count=32 bs=512 conv=fsync ) > /dev/null 2>&1
elif [[ \$DPKG_MAINTSCRIPT_PACKAGE == *odroidc2* ]] ; then
	( dd if=/usr/lib/$uboot_name/bl1.bin.hardkernel of=\$DEVICE bs=1 count=442 conv=fsync ) > /dev/null 2>&1
	( dd if=/usr/lib/$uboot_name/bl1.bin.hardkernel of=\$DEVICE bs=512 skip=1 seek=1 conv=fsync ) > /dev/null 2>&1
	( dd if=/usr/lib/$uboot_name/u-boot.bin of=\$DEVICE bs=512 seek=97 conv=fsync ) > /dev/null 2>&1
	( dd if=/dev/zero of=\$DEVICE seek=1249 count=799 bs=512 conv=fsync ) > /dev/null 2>&1 
elif [[ \$DPKG_MAINTSCRIPT_PACKAGE == *udoo* ]] ; then
	( dd if=/usr/lib/$uboot_name/SPL of=\$DEVICE bs=1k seek=1 status=noxfer ) > /dev/null 2>&1
	( dd if=/usr/lib/$uboot_name/u-boot.img of=\$DEVICE bs=1K seek=69 status=noxfer ) > /dev/null 2>&1
elif [[ \$DPKG_MAINTSCRIPT_PACKAGE == *armada* ]] ; then
	( dd if=/usr/lib/$uboot_name/u-boot.mmc of=\$DEVICE bs=512 seek=1 status=noxfer ) > /dev/null 2>&1
else
	( dd if=/dev/zero of=\$DEVICE bs=1k count=1023 seek=1 status=noxfer ) > /dev/null 2>&1
	( dd if=/usr/lib/$uboot_name/u-boot-sunxi-with-spl.bin of=\$DEVICE bs=1024 seek=8 status=noxfer ) > /dev/null 2>&1
fi
exit 0
END
#

chmod 755 $DEST/debs/$uboot_name/DEBIAN/postinst
# set up control file
cat <<END > $DEST/debs/$uboot_name/DEBIAN/control
Package: linux-u-boot-${BOARD}-${BRANCH}
Version: $REVISION
Architecture: $ARCH
Maintainer: $MAINTAINER <$MAINTAINERMAIL>
Installed-Size: 1
Section: kernel
Priority: optional
Description: Uboot loader $VER
END
#

	# copy proper uboot files to place
	if [[ $BOARD == cubox-i* ]] ; then
		[ ! -f "SPL" ] || cp SPL u-boot.img $DEST/debs/$uboot_name/usr/lib/$uboot_name
	elif [[ $BOARD == guitar* ]] ; then
		[ ! -f "u-boot-dtb.bin" ] || cp u-boot-dtb.bin $DEST/debs/$uboot_name/usr/lib/$uboot_name
		[ ! -f "$SRC/lib/bin/s500-bootloader.bin" ] || cp $SRC/lib/bin/s500-bootloader.bin $DEST/debs/$uboot_name/usr/lib/$uboot_name/bootloader.bin
	elif [[ $BOARD == odroidxu4 ]] ; then
		[ ! -f "sd_fuse/hardkernel/bl1.bin.hardkernel" ] || cp sd_fuse/hardkernel/bl1.bin.hardkernel $DEST/debs/$uboot_name/usr/lib/$uboot_name
		[ ! -f "sd_fuse/hardkernel/bl2.bin.hardkernel" ] || cp sd_fuse/hardkernel/bl2.bin.hardkernel $DEST/debs/$uboot_name/usr/lib/$uboot_name
		[ ! -f "sd_fuse/hardkernel/tzsw.bin.hardkernel" ] || cp sd_fuse/hardkernel/tzsw.bin.hardkernel $DEST/debs/$uboot_name/usr/lib/$uboot_name
		[ ! -f "u-boot.bin" ] || cp u-boot.bin $DEST/debs/$uboot_name/usr/lib/$uboot_name/
	elif [[ $BOARD == odroidc1 ]] ; then
		[ ! -f "sd_fuse/bl1.bin.hardkernel" ] || cp sd_fuse/bl1.bin.hardkernel $DEST/debs/$uboot_name/usr/lib/$uboot_name		
		[ ! -f "sd_fuse/u-boot.bin" ] || cp sd_fuse/u-boot.bin $DEST/debs/$uboot_name/usr/lib/$uboot_name
	elif [[ $BOARD == odroidc2 ]] ; then
		[ ! -f "sd_fuse/bl1.bin.hardkernel" ] || cp sd_fuse/bl1.bin.hardkernel $DEST/debs/$uboot_name/usr/lib/$uboot_name		
		[ ! -f "build/u-boot.bin" ] || cp build/u-boot.bin $DEST/debs/$uboot_name/usr/lib/$uboot_name
	elif [[ $BOARD == udoo* ]] ; then
		[ ! -f "u-boot.img" ] || cp SPL u-boot.img $DEST/debs/$uboot_name/usr/lib/$uboot_name
	elif [[ $BOARD == armada* ]] ; then
		[ ! -f "u-boot.mmc" ] || cp u-boot.mmc $DEST/debs/$uboot_name/usr/lib/$uboot_name
	else
		[ ! -f "u-boot-sunxi-with-spl.bin" ] || cp u-boot-sunxi-with-spl.bin $DEST/debs/$uboot_name/usr/lib/$uboot_name
	fi

	cd $DEST/debs
	display_alert "Target directory" "$DEST/debs/" "info"
	display_alert "Building deb" "$uboot_name.deb" "info"
	dpkg -b $uboot_name > /dev/null
	rm -rf $uboot_name

	FILESIZE=$(wc -c $DEST/debs/$uboot_name.deb | cut -f 1 -d ' ')

	if [[ $FILESIZE -lt 50000 ]]; then
		rm $DEST/debs/$uboot_name.deb
		exit_with_error "Building u-boot failed, check configuration"
	fi
}

compile_sunxi_tools (){
#---------------------------------------------------------------------------------------------------------------------------------
# https://github.com/linux-sunxi/sunxi-tools Tools to help hacking Allwinner devices
#---------------------------------------------------------------------------------------------------------------------------------

	display_alert "Compiling sunxi tools" "@host & target" "info"
	cd $SOURCES/$MISC1_DIR
	make -s clean >/dev/null 2>&1
	rm -f sunxi-fexc sunxi-nand-part
	make -s >/dev/null 2>&1
	cp fex2bin bin2fex /usr/local/bin/
	# make -s clean >/dev/null 2>&1
	# rm -f sunxi-fexc sunxi-nand-part meminfo sunxi-fel sunxi-pio 2>/dev/null
	# make $CTHREADS 'sunxi-nand-part' CC=$CROSS_COMPILE"gcc" >> $DEST/debug/install.log 2>&1
	# make $CTHREADS 'sunxi-fexc' CC=$CROSS_COMPILE"gcc" >> $DEST/debug/install.log 2>&1
	# make $CTHREADS 'meminfo' CC=$CROSS_COMPILE"gcc" >> $DEST/debug/install.log 2>&1

}


compile_kernel (){
#---------------------------------------------------------------------------------------------------------------------------------
# Compile kernel
#---------------------------------------------------------------------------------------------------------------------------------

	if [[ ! -d "$SOURCES/$LINUXSOURCEDIR" ]]; then
		exit_with_error "Error building kernel: source directory does not exist" "$LINUXSOURCEDIR"
	fi

	# read kernel version to variable $VER
	grab_version "$SOURCES/$LINUXSOURCEDIR"

	display_alert "Compiling $BRANCH kernel" "@host" "info"
	cd $SOURCES/$LINUXSOURCEDIR/

	# adding custom firmware to kernel source
	if [[ -n "$FIRMWARE" ]]; then unzip -o $SRC/lib/$FIRMWARE -d $SOURCES/$LINUXSOURCEDIR/firmware; fi

	# use proven config
	if [ "$KERNEL_KEEP_CONFIG" != "yes" ] || [ ! -f $SOURCES/$LINUXSOURCEDIR/.config ]; then
		if [ -f $SRC/userpatches/$LINUXCONFIG.config ]; then
			display_alert "Using kernel config provided by user" "userpatches/$LINUXCONFIG.config" "info"
			cp $SRC/userpatches/$LINUXCONFIG.config $SOURCES/$LINUXSOURCEDIR/.config
		else
			display_alert "Using kernel config file" "lib/config/$LINUXCONFIG.config" "info"
			cp $SRC/lib/config/$LINUXCONFIG.config $SOURCES/$LINUXSOURCEDIR/.config
		fi
	fi

	# hacks for banana family
	if [[ $LINUXFAMILY == "banana" ]] ; then
		sed -i 's/CONFIG_GMAC_CLK_SYS=y/CONFIG_GMAC_CLK_SYS=y\nCONFIG_GMAC_FOR_BANANAPI=y/g' .config
	fi

	# hack for deb builder. To pack what's missing in headers pack.
	cp $SRC/lib/patch/misc/headers-debian-byteshift.patch /tmp

	export LOCALVERSION="-"$LINUXFAMILY
	
	if [[ $ARCH == *64* ]]; then ARCHITECTURE=arm64; else ARCHITECTURE=arm; fi

	# We can use multi threading here but not later since it's not working. This way of compilation is much faster.
	if [ "$KERNEL_CONFIGURE" != "yes" ]; then
		if [ "$BRANCH" = "default" ]; then
			make $CTHREADS ARCH=$ARCHITECTURE CROSS_COMPILE=$CROSS_COMPILE silentoldconfig
		else
			make $CTHREADS ARCH=$ARCHITECTURE CROSS_COMPILE=$CROSS_COMPILE olddefconfig
		fi
	else
		make $CTHREADS ARCH=$ARCHITECTURE CROSS_COMPILE=$CROSS_COMPILE oldconfig
		make $CTHREADS ARCH=$ARCHITECTURE CROSS_COMPILE=$CROSS_COMPILE menuconfig
	fi

	eval 'make $CTHREADS ARCH=$ARCHITECTURE CROSS_COMPILE="$CCACHE $CROSS_COMPILE" $TARGETS modules 2>&1' \
		${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/compilation.log'} \
		${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Compiling kernel..." $TTY_Y $TTY_X'} \
		${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

	if [ ${PIPESTATUS[0]} -ne 0 ] || [ ! -f arch/$ARCHITECTURE/boot/$TARGETS ]; then
			exit_with_error "Kernel was not built" "@host"
	fi
	eval 'make $CTHREADS ARCH=$ARCHITECTURE CROSS_COMPILE="$CCACHE $CROSS_COMPILE" dtbs 2>&1' \
		${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/compilation.log'} \
		${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Compiling Device Tree..." $TTY_Y $TTY_X'} \
		${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

	if [ ${PIPESTATUS[0]} -ne 0 ]; then
		exit_with_error "DTBs were not build" "@host"
	fi


	# different packaging for 4.3+ // probably temporaly soution
	KERNEL_PACKING="deb-pkg"
	IFS='.' read -a array <<< "$VER"
	if (( "${array[0]}" == "4" )) && (( "${array[1]}" >= "3" )); then
		KERNEL_PACKING="bindeb-pkg"
	fi

	# make $CTHREADS ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE
	# produce deb packages: image, headers, firmware, libc
	eval 'make -j1 $KERNEL_PACKING KDEB_PKGVERSION=$REVISION LOCALVERSION="-"$LINUXFAMILY KBUILD_DEBARCH=$ARCH ARCH=$ARCHITECTURE DEBFULLNAME="$MAINTAINER" \
		DEBEMAIL="$MAINTAINERMAIL" CROSS_COMPILE="$CCACHE $CROSS_COMPILE" 2>&1 ' \
		${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/compilation.log'} \
		${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Creating kernel packages..." $TTY_Y $TTY_X'} \
		${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

	cd ..
	mv *.deb $DEST/debs/ || exit_with_error "Failed moving kernel DEBs"
}


install_external_applications (){
#--------------------------------------------------------------------------------------------------------------------------------
# Install external applications example
#--------------------------------------------------------------------------------------------------------------------------------
display_alert "Installing external applications" "USB redirector" "info"
# USB redirector tools http://www.incentivespro.com
cd $SOURCES
wget -q http://www.incentivespro.com/usb-redirector-linux-arm-eabi.tar.gz
tar xfz usb-redirector-linux-arm-eabi.tar.gz
rm usb-redirector-linux-arm-eabi.tar.gz
cd $SOURCES/usb-redirector-linux-arm-eabi/files/modules/src/tusbd
# patch to work with newer kernels
sed -e "s/f_dentry/f_path.dentry/g" -i usbdcdev.c
make -j1 ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE KERNELDIR=$SOURCES/$LINUXSOURCEDIR/ >> $DEST/debug/install.log
# configure USB redirector
sed -e 's/%INSTALLDIR_TAG%/\/usr\/local/g' $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd > $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd1
sed -e 's/%PIDFILE_TAG%/\/var\/run\/usbsrvd.pid/g' $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd1 > $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd
sed -e 's/%STUBNAME_TAG%/tusbd/g' $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd > $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd1
sed -e 's/%DAEMONNAME_TAG%/usbsrvd/g' $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd1 > $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd
chmod +x $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd
# copy to root
cp $SOURCES/usb-redirector-linux-arm-eabi/files/usb* $CACHEDIR/sdcard/usr/local/bin/
cp $SOURCES/usb-redirector-linux-arm-eabi/files/modules/src/tusbd/tusbd.ko $CACHEDIR/sdcard/usr/local/bin/
cp $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd $CACHEDIR/sdcard/etc/init.d/
# not started by default ----- update.rc rc.usbsrvd defaults
# chroot $CACHEDIR/sdcard /bin/bash -c "update-rc.d rc.usbsrvd defaults"

# some aditional stuff. Some driver as example
if [[ -n "$MISC3_DIR" ]]; then
	display_alert "Installing external applications" "RT8192 driver" "info"
	# https://github.com/pvaret/rtl8192cu-fixes
	cd $SOURCES/$MISC3_DIR
	#git checkout 0ea77e747df7d7e47e02638a2ee82ad3d1563199
	make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE clean >/dev/null 2>&1
	(make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE KSRC=$SOURCES/$LINUXSOURCEDIR/ >/dev/null 2>&1)
	cp *.ko $CACHEDIR/sdcard/lib/modules/$VER-$LINUXFAMILY/kernel/net/wireless/
	depmod -b $CACHEDIR/sdcard/ $VER-$LINUXFAMILY
	#cp blacklist*.conf $CACHEDIR/sdcard/etc/modprobe.d/
fi

# MISC4 = NOTRO DRIVERS / special handling

# MISC5 = sunxi display control
if [[ -n "$MISC5_DIR" && $BRANCH != "next" && $LINUXSOURCEDIR == *sunxi* ]]; then
	cd "$SOURCES/$MISC5_DIR"
	cp "$SOURCES/$LINUXSOURCEDIR/include/video/sunxi_disp_ioctl.h" .
	make clean >/dev/null 2>&1
	(make ARCH=$ARCH CC=$CROSS_COMPILE"gcc" KSRC="$SOURCES/$LINUXSOURCEDIR/" >/dev/null 2>&1)
	install -m 755 a10disp "$CACHEDIR/sdcard/usr/local/bin"
fi
# MISC5 = sunxi display control / compile it for sun8i just in case sun7i stuff gets ported to sun8i and we're able to use it
if [[ -n "$MISC5_DIR" && $BRANCH != "next" && $LINUXSOURCEDIR == *sun8i* ]]; then
	cd "$SOURCES/$MISC5_DIR"
	wget -q "https://raw.githubusercontent.com/linux-sunxi/linux-sunxi/sunxi-3.4/include/video/sunxi_disp_ioctl.h"
	make clean >/dev/null 2>&1
	(make ARCH=$ARCH CC=$CROSS_COMPILEgcc KSRC="$SOURCES/$LINUXSOURCEDIR/" >/dev/null 2>&1)
	install -m 755 a10disp "$CACHEDIR/sdcard/usr/local/bin"
fi

# MT7601U
if [[ -n "$MISC6_DIR" && $BRANCH != "next" ]]; then
	display_alert "Installing external applications" "MT7601U - driver" "info"
	cd $SOURCES/$MISC6_DIR
	cat >> fix_build.patch << _EOF_
diff --git a/src/dkms.conf b/src/dkms.conf
new file mode 100644
index 0000000..7563b5a
--- /dev/null
+++ b/src/dkms.conf
@@ -0,0 +1,8 @@
+PACKAGE_NAME="mt7601-sta-dkms"
+PACKAGE_VERSION="3.0.0.4"
+CLEAN="make clean"
+BUILT_MODULE_NAME[0]="mt7601Usta"
+BUILT_MODULE_LOCATION[0]="./os/linux/"
+DEST_MODULE_LOCATION[0]="/kernel/drivers/net/wireless"
+AUTOINSTALL=yes
+MAKE[0]="make -j4 KERNELVER=\$kernelver"
diff --git a/src/include/os/rt_linux.h b/src/include/os/rt_linux.h
index 3726b9e..b8be886 100755
--- a/src/include/os/rt_linux.h
+++ b/src/include/os/rt_linux.h
@@ -279,7 +279,7 @@ typedef struct file* RTMP_OS_FD;
 
 typedef struct _OS_FS_INFO_
 {
-#if LINUX_VERSION_CODE >= KERNEL_VERSION(3,12,0)
+#if LINUX_VERSION_CODE >= KERNEL_VERSION(3,4,0)
 	uid_t				fsuid;
 	gid_t				fsgid;
 #else
diff --git a/src/os/linux/rt_linux.c b/src/os/linux/rt_linux.c
index 1b6a631..c336611 100755
--- a/src/os/linux/rt_linux.c
+++ b/src/os/linux/rt_linux.c
@@ -51,7 +51,7 @@
 #define RT_CONFIG_IF_OPMODE_ON_STA(__OpMode)
 #endif
 
-ULONG RTDebugLevel = RT_DEBUG_TRACE;
+ULONG RTDebugLevel = 0;
 ULONG RTDebugFunc = 0;
 
 #ifdef OS_ABL_FUNC_SUPPORT
_EOF_

	patch -f -s -p1 -r - <fix_build.patch >/dev/null
	cd src
	make -s ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE clean >/dev/null 2>&1
	(make -s -j4 ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE LINUX_SRC=$SOURCES/$LINUXSOURCEDIR/ >/dev/null 2>&1)
	cp os/linux/*.ko $CACHEDIR/sdcard/lib/modules/$VER-$LINUXFAMILY/kernel/net/wireless/
	mkdir -p $CACHEDIR/sdcard/etc/Wireless/RT2870STA
	cp RT2870STA.dat $CACHEDIR/sdcard/etc/Wireless/RT2870STA/
	depmod -b $CACHEDIR/sdcard/ $VER-$LINUXFAMILY
	make -s clean 1>&2 2>/dev/null
	cd ..
	mkdir -p $CACHEDIR/sdcard/usr/src/
	cp -R src $CACHEDIR/sdcard/usr/src/mt7601-3.0.0.4
	# TODO: Set the module to build automatically via dkms in the future here

fi

# h3disp for sun8i/3.4.x
if [ "$BOARD" = "orangepiplus" -o "$BOARD" = "orangepih3" ]; then
	install -m 755 "$SRC/lib/scripts/h3disp" "$CACHEDIR/sdcard/usr/local/bin"
fi
}

# write_uboot <loopdev>
#
# writes u-boot to loop device
# Parameters:
# loopdev: loop device with mounted rootfs image
write_uboot()
{
	LOOP=$1
	display_alert "Writing bootloader" "$LOOP" "info"
	dpkg -x ${DEST}/debs/${CHOSEN_UBOOT}_${REVISION}_${ARCH}.deb /tmp/

	if [[ $BOARD == *cubox* ]] ; then
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/SPL of=$LOOP bs=512 seek=2 status=noxfer >/dev/null 2>&1)
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/u-boot.img of=$LOOP bs=1K seek=42 status=noxfer >/dev/null 2>&1)
	elif [[ $BOARD == *armada* ]] ; then
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/u-boot.mmc of=$LOOP bs=512 seek=1 status=noxfer >/dev/null 2>&1)
	elif [[ $BOARD == *udoo* ]] ; then
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/SPL of=$LOOP bs=1k seek=1 status=noxfer >/dev/null 2>&1)
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/u-boot.img of=$LOOP bs=1k seek=69 conv=fsync >/dev/null 2>&1)
	elif [[ $BOARD == *guitar* ]] ; then
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/bootloader.bin of=$LOOP bs=512 seek=4097 conv=fsync > /dev/null 2>&1)
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/u-boot-dtb.bin of=$LOOP bs=512 seek=6144 conv=fsync > /dev/null 2>&1)
	elif [[ $BOARD == *odroidxu4* ]] ; then
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/bl1.bin.hardkernel of=$LOOP seek=1 conv=fsync ) > /dev/null 2>&1
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/bl2.bin.hardkernel of=$LOOP seek=31 conv=fsync ) > /dev/null 2>&1
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/u-boot.bin of=$LOOP bs=512 seek=63 conv=fsync ) > /dev/null 2>&1
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/tzsw.bin.hardkernel of=$LOOP seek=719 conv=fsync ) > /dev/null 2>&1
		( dd if=/dev/zero of=$LOOP seek=1231 count=32 bs=512 conv=fsync ) > /dev/null 2>&1		
	elif [[ $BOARD == *odroidc1* ]] ; then
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/bl1.bin.hardkernel of=$LOOP bs=1 count=442 conv=fsync ) > /dev/null 2>&1	
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/bl1.bin.hardkernel of=$LOOP bs=512 skip=1 seek=1 conv=fsync ) > /dev/null 2>&1	
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/u-boot.bin of=$LOOP bs=512 seek=64 conv=fsync ) > /dev/null 2>&1	
		( dd if=/dev/zero of=$LOOP seek=1024 count=32 bs=512 conv=fsync ) > /dev/null 2>&1
	elif [[ $BOARD == *odroidc2* ]] ; then
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/bl1.bin.hardkernel of=$LOOP bs=1 count=442 conv=fsync ) > /dev/null 2>&1
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/bl1.bin.hardkernel of=$LOOP bs=512 skip=1 seek=1 conv=fsync ) > /dev/null 2>&1
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/u-boot.bin of=$LOOP bs=512 seek=97 conv=fsync ) > /dev/null 2>&1
		( dd if=/dev/zero of=$LOOP seek=1249 count=799 bs=512 conv=fsync ) > /dev/null 2>&1
	else
		( dd if=/dev/zero of=$LOOP bs=1k count=1023 seek=1 status=noxfer ) > /dev/null 2>&1
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/u-boot-sunxi-with-spl.bin of=$LOOP bs=1024 seek=8 status=noxfer >/dev/null 2>&1)
	fi
	if [ $? -ne 0 ]; then
		exit_with_error "U-boot failed to install" "@host"
	fi
	rm -r /tmp/usr
	sync
}

customize_image()
{
	cp $SRC/userpatches/customize-image.sh $CACHEDIR/sdcard/tmp/customize-image.sh
	chmod +x $CACHEDIR/sdcard/tmp/customize-image.sh
	mkdir -p $CACHEDIR/sdcard/tmp/overlay
	mount --bind $SRC/userpatches/overlay $CACHEDIR/sdcard/tmp/overlay
	display_alert "Calling image customization script" "customize-image.sh" "info"
	chroot $CACHEDIR/sdcard /bin/bash -c "/tmp/customize-image.sh $RELEASE $FAMILY $BOARD $BUILD_DESKTOP"
	umount $CACHEDIR/sdcard/tmp/overlay
}
