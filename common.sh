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


compile_uboot (){
#--------------------------------------------------------------------------------------------------------------------------------
# Compile uboot from sources
#--------------------------------------------------------------------------------------------------------------------------------

if [ -d "$SOURCES/$BOOTSOURCE" ]; then
	cd $SOURCES/$BOOTSOURCE
		make -s ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- clean >/dev/null 2>&1
	# there are two methods of compilation
	if [[ $BOOTCONFIG == *config* ]]; then
		make $CTHREADS $BOOTCONFIG CROSS_COMPILE=arm-linux-gnueabihf- >/dev/null 2>&1
		sed -i 's/CONFIG_LOCALVERSION=""/CONFIG_LOCALVERSION="-armbian"/g' .config
		sed -i 's/CONFIG_LOCALVERSION_AUTO=.*/# CONFIG_LOCALVERSION_AUTO is not set/g' .config
		touch .scmversion
		if [[ $BRANCH != "next" && $LINUXCONFIG == *sun* ]] ; then
			## patch mainline uboot configuration to boot with old kernels
			if [ "$(cat $SOURCES/$BOOTSOURCE/.config | grep CONFIG_ARMV7_BOOT_SEC_DEFAULT=y)" == "" ]; then
				echo "CONFIG_ARMV7_BOOT_SEC_DEFAULT=y" >> $SOURCES/$BOOTSOURCE/.config
#				echo "CONFIG_ARMV7_BOOT_SEC_DEFAULT=y" >> $SOURCES/$BOOTSOURCE/spl/.config
				echo "CONFIG_OLD_SUNXI_KERNEL_COMPAT=y" >> $SOURCES/$BOOTSOURCE/.config
#				echo "CONFIG_OLD_SUNXI_KERNEL_COMPAT=y"	>> $SOURCES/$BOOTSOURCE/spl/.config
			fi
		fi
	make $CTHREADS CROSS_COMPILE=arm-linux-gnueabihf- 2>&1 | dialog  --progressbox "Compiling universal boot loader..." 20 70
else
	make $CTHREADS $BOOTCONFIG CROSS_COMPILE=arm-linux-gnueabihf- 2>&1 | dialog  --progressbox "Compiling universal boot loader..." 20 70
fi

grab_u-boot_version


# create .deb package
#
if [[ $BRANCH == "next" ]] ; then
	UBOOT_BRACH="-next"
	else
	UBOOT_BRACH=""
fi 
CHOOSEN_UBOOT="linux-u-boot"$UBOOT_BRACH"-"$BOARD"_"$REVISION"_armhf"
UBOOT_PCK="linux-u-boot-"$BOARD""$UBOOT_BRACH
mkdir -p $DEST/debs/$CHOOSEN_UBOOT/usr/lib/$CHOOSEN_UBOOT
mkdir -p $DEST/debs/$CHOOSEN_UBOOT/DEBIAN
# set up post install script
cat <<END > $DEST/debs/$CHOOSEN_UBOOT/DEBIAN/postinst
#!/bin/bash
set -e
if [[ \$DEVICE == "" ]]; then DEVICE="/dev/mmcblk0"; fi

if [[ \$DPKG_MAINTSCRIPT_PACKAGE == *cubox* ]] ; then 
	( dd if=/usr/lib/$CHOOSEN_UBOOT/SPL of=\$DEVICE bs=512 seek=2 status=noxfer ) > /dev/null 2>&1
	( dd if=/usr/lib/$CHOOSEN_UBOOT/u-boot.img of=\$DEVICE bs=1K seek=42 status=noxfer ) > /dev/null 2>&1	
elif [[ \$DPKG_MAINTSCRIPT_PACKAGE == *udoo* ]] ; then 
	( dd if=/usr/lib/$CHOOSEN_UBOOT/u-boot.imx of=\$DEVICE bs=1024 seek=1 conv=fsync ) > /dev/null 2>&1
else 
	( dd if=/usr/lib/$CHOOSEN_UBOOT/u-boot-sunxi-with-spl.bin of=\$DEVICE bs=1024 seek=8 status=noxfer ) > /dev/null 2>&1	
fi
exit 0
END

chmod 755 $DEST/debs/$CHOOSEN_UBOOT/DEBIAN/postinst
# set up control file
cat <<END > $DEST/debs/$CHOOSEN_UBOOT/DEBIAN/control
Package: linux-u-boot-$BOARD$UBOOT_BRACH
Version: $REVISION
Architecture: armhf
Maintainer: $MAINTAINER <$MAINTAINERMAIL>
Installed-Size: 1
Section: kernel
Priority: optional
Description: Uboot loader $UBOOTVER
END
#

if [[ $BOARD == cubox-i* ]] ; then
	[ ! -f "SPL" ] || cp SPL u-boot.img $DEST/debs/$CHOOSEN_UBOOT/usr/lib/$CHOOSEN_UBOOT
elif [[ $BOARD == udoo* ]] ; then
	[ ! -f "u-boot.imx" ] || cp u-boot.imx $DEST/debs/$CHOOSEN_UBOOT/usr/lib/$CHOOSEN_UBOOT
else
	[ ! -f "u-boot-sunxi-with-spl.bin" ] || cp u-boot-sunxi-with-spl.bin $DEST/debs/$CHOOSEN_UBOOT/usr/lib/$CHOOSEN_UBOOT 
fi

cd $DEST/debs
display_alert "Building deb" "$CHOOSEN_UBOOT.deb" "info"
dpkg -b $CHOOSEN_UBOOT >/dev/null 2>&1
rm -rf $CHOOSEN_UBOOT
#

FILESIZE=$(wc -c $DEST/debs/$CHOOSEN_UBOOT'.deb' | cut -f 1 -d ' ')
if [ $FILESIZE -lt 50000 ]; then
	display_alert "Building failed, check configuration." "$CHOOSEN_UBOOT deleted" "err"
	rm $DEST/debs/$CHOOSEN_UBOOT".deb"
	exit
fi
else
display_alert "Source file $1 does not exists. Check fetch_from_github configuration." "" "err"
fi
}


compile_sunxi_tools (){
#--------------------------------------------------------------------------------------------------------------------------------
# Compile sunxi_tools
#--------------------------------------------------------------------------------------------------------------------------------
display_alert "Compiling sunxi tools" "@host & target" "info"

cd $SOURCES/sunxi-tools
# for host
make -s clean >/dev/null 2>&1
make -s fex2bin >/dev/null 2>&1
make -s bin2fex >/dev/null 2>&1 
cp fex2bin bin2fex /usr/local/bin/
# for destination
make -s clean >/dev/null 2>&1
make $CTHREADS 'fex2bin' CC=arm-linux-gnueabi-gcc >/dev/null 2>&1
make $CTHREADS 'bin2fex' CC=arm-linux-gnueabi-gcc >/dev/null 2>&1
make $CTHREADS 'nand-part' CC=arm-linux-gnueabi-gcc >/dev/null 2>&1
}


compile_kernel (){
#--------------------------------------------------------------------------------------------------------------------------------
# Compile kernel
#--------------------------------------------------------------------------------------------------------------------------------
display_alert "Compiling kernel" "@host" "info"
sleep 2

if [ -d "$SOURCES/$LINUXSOURCE" ]; then 

cd $SOURCES/$LINUXSOURCE
# delete previous creations
if [ "$KERNEL_CLEAN" = "yes" ]; then make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- clean | dialog  --progressbox "Cleaning kernel source ..." 20 70; fi

# adding custom firmware to kernel source
if [[ -n "$FIRMWARE" ]]; then unzip -o $SRC/lib/$FIRMWARE -d $SOURCES/$LINUXSOURCE/firmware; fi

# use proven config
cp $SRC/lib/config/$LINUXCONFIG.config $SOURCES/$LINUXSOURCE/.config

# hacks for banana
if [[ $BOARD == banana* || $BOARD == orangepi* || $BOARD == lamobo* ]] ; then
sed -i 's/CONFIG_GMAC_CLK_SYS=y/CONFIG_GMAC_CLK_SYS=y\nCONFIG_GMAC_FOR_BANANAPI=y/g' .config
fi

# hack for deb builder. To pack what's missing in headers pack.
cp $SRC/lib/patch/misc/headers-debian-byteshift.patch /tmp

if [ "$KERNEL_CONFIGURE" = "yes" ]; then make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- menuconfig; fi

export LOCALVERSION="-"$LINUXFAMILY 

# this way of compilation is much faster. We can use multi threading here but not later
make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- oldconfig
make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- all zImage | dialog  --progressbox "Compiling kernel ..." 20 70
# make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- 
# produce deb packages: image, headers, firmware, libc
make -j1 deb-pkg KDEB_PKGVERSION=$REVISION LOCALVERSION="-"$LINUXFAMILY KBUILD_DEBARCH=armhf ARCH=arm DEBFULLNAME="$MAINTAINER" \
DEBEMAIL="$MAINTAINERMAIL" CROSS_COMPILE=arm-linux-gnueabihf- | dialog  --progressbox "Packaging kernel ..." 20 70

if [[ $BRANCH == "next" ]] ; then
	KERNEL_BRACH="-next"
	else
	KERNEL_BRACH=""
fi 

# we need a name
CHOOSEN_KERNEL=linux-image"$KERNEL_BRACH"-"$CONFIG_LOCALVERSION$LINUXFAMILY"_"$REVISION"_armhf.deb
cd ..
mv *.deb $DEST/debs/ || exit
else
display_alert "Source file $1 does not exists. Check fetch_from_github configuration." "" "err"
exit
fi
sync
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
make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- KERNELDIR=$SOURCES/$LINUXSOURCE/
# configure USB redirector
sed -e 's/%INSTALLDIR_TAG%/\/usr\/local/g' $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd > $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd1
sed -e 's/%PIDFILE_TAG%/\/var\/run\/usbsrvd.pid/g' $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd1 > $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd
sed -e 's/%STUBNAME_TAG%/tusbd/g' $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd > $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd1
sed -e 's/%DAEMONNAME_TAG%/usbsrvd/g' $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd1 > $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd
chmod +x $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd
# copy to root
cp $SOURCES/usb-redirector-linux-arm-eabi/files/usb* $DEST/cache/sdcard/usr/local/bin/ 
cp $SOURCES/usb-redirector-linux-arm-eabi/files/modules/src/tusbd/tusbd.ko $DEST/cache/sdcard/usr/local/bin/ 
cp $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd $DEST/cache/sdcard/etc/init.d/
# not started by default ----- update.rc rc.usbsrvd defaults
# chroot $DEST/cache/sdcard /bin/bash -c "update-rc.d rc.usbsrvd defaults"


# some aditional stuff. Some driver as example
if [[ -n "$MISC3_DIR" ]]; then
	display_alert "Installing external applications" "RT8192 driver" "info"
	# https://github.com/pvaret/rtl8192cu-fixes
	cd $SOURCES/$MISC3_DIR
	#git checkout 0ea77e747df7d7e47e02638a2ee82ad3d1563199
	make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- clean >/dev/null 2>&1
	make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- KSRC=$SOURCES/$LINUXSOURCE/
	cp *.ko $DEST/cache/sdcard/usr/local/bin
	#cp blacklist*.conf $DEST/cache/sdcard/etc/modprobe.d/
fi

# MISC4 = NOTRO DRIVERS / special handling
# MISC5 = sunxu display control

if [[ -n "$MISC5_DIR" && $BRANCH != "next" && $LINUXSOURCE == *sunxi*  ]]; then
	cd $SOURCES/$MISC5_DIR
	cp $SOURCES/$LINUXSOURCE/include/video/sunxi_disp_ioctl.h .
	make clean >/dev/null 2>&1
	make $CTHREADS ARCH=arm CC=arm-linux-gnueabi-gcc KSRC=$SOURCES/$LINUXSOURCE/ >/dev/null 2>&1
	install -m 755 a10disp $DEST/cache/sdcard/usr/local/bin
fi

}


shrinking_raw_image (){
#--------------------------------------------------------------------------------------------------------------------------------
# Shrink partition and image to real size with 10% space
#--------------------------------------------------------------------------------------------------------------------------------
RAWIMAGE=$1
display_alert "Shrink image last partition to" "minimum" "info"
# partition prepare
LOOP=$(losetup -f)
losetup $LOOP $RAWIMAGE
PARTSTART=$(fdisk -l $LOOP | grep $LOOP | grep Linux | awk '{ print $2}')
PARTSTART=$(($PARTSTART*512))
sleep 1; losetup -d $LOOP
sleep 1; losetup -o $PARTSTART $LOOP $RAWIMAGE
sleep 1; fsck -n $LOOP >/dev/null 2>&1
sleep 1; tune2fs -O ^has_journal $LOOP >/dev/null 2>&1
sleep 1; e2fsck -fy $LOOP >/dev/null 2>&1
resize2fs $LOOP -M >/dev/null 2>&1
BLOCKSIZE=$(LANGUAGE=english dumpe2fs -h $LOOP | grep "Block count" | awk '{ print $(NF)}')
NEWSIZE=$(($BLOCKSIZE*4500/1024)) # overhead hardcoded to number
BLOCKSIZE=$(LANGUAGE=english resize2fs $LOOP $NEWSIZE"K" >/dev/null 2>&1)
sleep 1; tune2fs -O has_journal $LOOP >/dev/null 2>&1
sleep 1; tune2fs -o journal_data_writeback $LOOP >/dev/null 2>&1
sleep 1; losetup -d $LOOP

# mount once again and create new partition
sleep 1; losetup $LOOP $RAWIMAGE
PARTITIONS=$(($(fdisk -l $LOOP | grep $LOOP | wc -l)-1))
((echo d; echo $PARTITIONS; echo n; echo p; echo ; echo ; echo "+"$NEWSIZE"K"; echo w;) | fdisk $LOOP)>/dev/null
sleep 1

# truncate the image
TRUNCATE=$(parted -m $LOOP 'unit s print' | tail -1 | awk -F':' '{ print $3 }' | sed 's/.$//')
TRUNCATE=$((($TRUNCATE+1)*512))
truncate -s $TRUNCATE $RAWIMAGE >/dev/null 2>&1
losetup -d $LOOP
}


closing_image (){
#--------------------------------------------------------------------------------------------------------------------------------
# Closing image and clean-up 									            
#--------------------------------------------------------------------------------------------------------------------------------
display_alert "Possible after install." "$AFTERINSTALL" "info"
chroot $DEST/cache/sdcard /bin/bash -c "$AFTERINSTALL"
chroot $DEST/cache/sdcard /bin/bash -c "sync"
sync
sleep 3
# unmount proc, sys and dev from chroot
umount -l $DEST/cache/sdcard/dev/pts
umount -l $DEST/cache/sdcard/dev
umount -l $DEST/cache/sdcard/proc
umount -l $DEST/cache/sdcard/sys
umount -l $DEST/cache/sdcard/tmp >/dev/null 2>&1

# let's create nice file name
VER="${VER/-$LINUXFAMILY/}"
VERSION=$VERSION" "$VER
VERSION="${VERSION// /_}"
VERSION="${VERSION//$BRANCH/}"
VERSION="${VERSION//__/_}"

if [ "$BUILD_DESKTOP" = "yes" ]; then
VERSION=$VERSION"_desktop"
fi
 

# kill process inside
KILLPROC=$(ps -uax | pgrep ntpd |        tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi  
KILLPROC=$(ps -uax | pgrep dbus-daemon | tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi  

# same info outside the image
cp $DEST/cache/sdcard/etc/armbian.txt $DEST/cache/
sleep 2
rm $DEST/cache/sdcard/usr/bin/qemu-arm-static 
sleep 2
umount -l $DEST/cache/sdcard/boot > /dev/null 2>&1 || /bin/true
umount -l $DEST/cache/sdcard/ 
sleep 2
losetup -d $LOOP
rm -rf $DEST/cache/sdcard/

# write bootloader
LOOP=$(losetup -f)
display_alert "Writing boot loader" "$LOOP" "info"
losetup $LOOP $DEST/cache/tmprootfs.raw
dpkg -x $DEST"/debs/"$CHOOSEN_UBOOT".deb" /tmp/

if [[ $BOARD == *cubox* ]] ; then 
	( dd if=/tmp/usr/lib/"$CHOOSEN_UBOOT"/SPL of=$LOOP bs=512 seek=2 status=noxfer >/dev/null 2>&1) 
	( dd if=/tmp/usr/lib/"$CHOOSEN_UBOOT"/u-boot.img of=$LOOP bs=1K seek=42 status=noxfer >/dev/null 2>&1) 	
elif [[ $BOARD == *udoo* ]] ; then 
	( dd if=/tmp/usr/lib/"$CHOOSEN_UBOOT"/u-boot.imx of=$LOOP bs=1024 seek=1 conv=fsync >/dev/null 2>&1) 
else 
	( dd if=/tmp/usr/lib/"$CHOOSEN_UBOOT"/u-boot-sunxi-with-spl.bin of=$LOOP bs=1024 seek=8 status=noxfer >/dev/null 2>&1) 	
fi
rm -r /tmp/usr
sync
sleep 3
losetup -d $LOOP
sync
sleep 2
mv $DEST/cache/tmprootfs.raw $DEST/cache/$VERSION.raw
sync
sleep 2
# let's shrint it
shrinking_raw_image "$DEST/cache/$VERSION.raw" "15"
sleep 2
cd $DEST/cache/
cp $SRC/lib/bin/imagewriter.exe .
# sign with PGP
if [[ $GPG_PASS != "" ]] ; then
	echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --batch --yes $VERSION.raw	
	echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --batch --yes imagewriter.exe
	echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --batch --yes armbian.txt
fi
display_alert "Create and sign" "$VERSION.zip" "info"
mkdir -p $DEST/images
zip -FSq $DEST/images/$VERSION.zip $VERSION.raw* armbian.txt imagewriter.*
#display_alert "Uploading to server" "$VERSION.zip" "info"
rm -f $VERSION.raw *.asc imagewriter.* armbian.txt
}
