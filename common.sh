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
# Image build functions
#

download_host_packages (){
#--------------------------------------------------------------------------------------------------------------------------------
# Download packages for host and install only if missing - Ubuntu 14.04 recommended                     
#--------------------------------------------------------------------------------------------------------------------------------
apt-get -y -qq install debconf-utils
PAKETKI="device-tree-compiler pv bc lzop zip binfmt-support bison build-essential ccache debootstrap flex gawk \
gcc-arm-linux-gnueabihf lvm2 qemu-user-static u-boot-tools uuid-dev zlib1g-dev unzip libusb-1.0-0-dev parted pkg-config \
expect gcc-arm-linux-gnueabi libncurses5-dev"
for x in $PAKETKI; do
	if [ $(dpkg-query -W -f='${Status}' $x 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
		INSTALL=$INSTALL" "$x
	fi
done
if [[ $INSTALL != "" ]]; then
debconf-apt-progress -- apt-get -y install $INSTALL 
fi
}


grab_kernel_version (){
#--------------------------------------------------------------------------------------------------------------------------------
# extract linux kernel version from Makefile
#--------------------------------------------------------------------------------------------------------------------------------
VER=$(cat $DEST/$LINUXSOURCE/Makefile | grep VERSION | head -1 | awk '{print $(NF)}')
VER=$VER.$(cat $DEST/$LINUXSOURCE/Makefile | grep PATCHLEVEL | head -1 | awk '{print $(NF)}')
VER=$VER.$(cat $DEST/$LINUXSOURCE/Makefile | grep SUBLEVEL | head -1 | awk '{print $(NF)}')
EXTRAVERSION=$(cat $DEST/$LINUXSOURCE/Makefile | grep EXTRAVERSION | head -1 | awk '{print $(NF)}')
if [ "$EXTRAVERSION" != "=" ]; then VER=$VER$EXTRAVERSION; fi
}


fetch_from_github (){
#--------------------------------------------------------------------------------------------------------------------------------
# Download sources from Github
#--------------------------------------------------------------------------------------------------------------------------------
echo -e "[\e[0;32m ok \x1B[0m] Downloading $2"
if [ -d "$DEST/$2" ]; then
	cd $DEST/$2
		# some patching for TFT display source and Realtek RT8192CU drivers
	if [[ $2 == "linux-sunxi" ]]; then 
		git checkout $FORCE -q HEAD 
	else
		git checkout $FORCE -q master
	fi
	git pull 
	cd $SRC
else
	git clone $1 $DEST/$2	
fi
}


compile_uboot (){
#--------------------------------------------------------------------------------------------------------------------------------
# Compile uboot
#--------------------------------------------------------------------------------------------------------------------------------
echo -e "[\e[0;32m ok \x1B[0m] Compiling universal boot loader"
if [ -d "$DEST/$BOOTSOURCE" ]; then
cd $DEST/$BOOTSOURCE
make -s CROSS_COMPILE=arm-linux-gnueabihf- clean
# there are two methods of compilation
if [[ $BOOTCONFIG == *config* ]]
then
	make $CTHREADS $BOOTCONFIG CROSS_COMPILE=arm-linux-gnueabihf-
		if [[ $BRANCH != "next" && $LINUXCONFIG == *sunxi* ]] ; then
			## patch mainline uboot configuration to boot with old kernels
			if [ "$(cat $DEST/$BOOTSOURCE/.config | grep CONFIG_ARMV7_BOOT_SEC_DEFAULT=y)" == "" ]; then
				echo "CONFIG_ARMV7_BOOT_SEC_DEFAULT=y" >> $DEST/$BOOTSOURCE/.config
				echo "CONFIG_ARMV7_BOOT_SEC_DEFAULT=y" >> $DEST/$BOOTSOURCE/spl/.config
				echo "CONFIG_OLD_SUNXI_KERNEL_COMPAT=y" >> $DEST/$BOOTSOURCE/.config
				echo "CONFIG_OLD_SUNXI_KERNEL_COMPAT=y"	>> $DEST/$BOOTSOURCE/spl/.config
			fi
		fi
	make $CTHREADS CROSS_COMPILE=arm-linux-gnueabihf-
else
	make $CTHREADS $BOOTCONFIG CROSS_COMPILE=arm-linux-gnueabihf- 
fi
# create .deb package
#
CHOOSEN_UBOOT="linux-u-boot-$VER-"$BOARD"_"$REVISION"_armhf"
UBOOT_PCK="linux-u-boot-$VER-"$BOARD
mkdir -p $DEST/output/u-boot/$CHOOSEN_UBOOT/usr/lib/$CHOOSEN_UBOOT
mkdir -p $DEST/output/u-boot/$CHOOSEN_UBOOT/DEBIAN
# set up post install script
cat <<END > $DEST/output/u-boot/$CHOOSEN_UBOOT/DEBIAN/postinst
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

chmod 755 $DEST/output/u-boot/$CHOOSEN_UBOOT/DEBIAN/postinst
# set up control file
cat <<END > $DEST/output/u-boot/$CHOOSEN_UBOOT/DEBIAN/control
Package: linux-u-boot-$VER-$BOARD
Version: $REVISION
Architecture: all
Maintainer: $MAINTAINER <$MAINTAINERMAIL>
Installed-Size: 1
Section: kernel
Priority: optional
Description: Uboot loader
END
#
if [[ $BOARD == cubox-i* ]] ; then
	cp SPL u-boot.img $DEST/output/u-boot/$CHOOSEN_UBOOT/usr/lib/$CHOOSEN_UBOOT
elif [[ $BOARD == udoo* ]] ; then
	cp u-boot.imx $DEST/output/u-boot/$CHOOSEN_UBOOT/usr/lib/$CHOOSEN_UBOOT
else
	cp u-boot-sunxi-with-spl.bin $DEST/output/u-boot/$CHOOSEN_UBOOT/usr/lib/$CHOOSEN_UBOOT
fi

cd $DEST/output/u-boot
dpkg -b $CHOOSEN_UBOOT
rm -rf $CHOOSEN_UBOOT
#

FILESIZE=$(wc -c $DEST/output/u-boot/$CHOOSEN_UBOOT'.deb' | cut -f 1 -d ' ')
if [ $FILESIZE -lt 50000 ]; then
	echo -e "[\e[0;31m Error \x1B[0m] Building failed, check configuration."
	exit
fi
else
echo "ERROR: Source file $1 does not exists. Check fetch_from_github configuration."
exit
fi
}


compile_sunxi_tools (){
#--------------------------------------------------------------------------------------------------------------------------------
# Compile sunxi_tools
#--------------------------------------------------------------------------------------------------------------------------------
echo -e "[\e[0;32m ok \x1B[0m] Compiling sunxi tools"
cd $DEST/sunxi-tools
# for host
make -s clean >/dev/null 2>&1
make -s fex2bin >/dev/null 2>&1
make -s bin2fex >/dev/null 2>&1 
cp fex2bin bin2fex /usr/local/bin/
# for destination
make -s clean >/dev/null 2>&1
make $CTHREADS 'fex2bin' CC=arm-linux-gnueabihf-gcc >/dev/null 2>&1
make $CTHREADS 'bin2fex' CC=arm-linux-gnueabihf-gcc >/dev/null 2>&1
make $CTHREADS 'nand-part' CC=arm-linux-gnueabihf-gcc >/dev/null 2>&1
}


add_fb_tft (){
#--------------------------------------------------------------------------------------------------------------------------------
# Adding FBTFT library / small TFT display support
#--------------------------------------------------------------------------------------------------------------------------------
# there is a change for kernel less than 3.5
IFS='.' read -a array <<< "$VER"
cd $DEST/$MISC4_DIR
if (( "${array[0]}" == "3" )) && (( "${array[1]}" < "5" ))
then
	git checkout -q 06f0bba152c036455ae76d26e612ff0e70a83a82
else
	git checkout -q master
fi
cd $DEST/$LINUXSOURCE
if [[ $BOARD == "bananapi" || $BOARD == "orangepi" ]]; then
	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/bananafbtft.patch | grep previ)" == "" ]; then
					# DMA disable
					patch --batch -N -p1 < $SRC/lib/patch/bananafbtft.patch
	fi
fi
# common patch
if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/small_lcd_drivers.patch | grep previ)" == "" ]; then
	patch -p1 < $SRC/lib/patch/small_lcd_drivers.patch
fi
}


compile_kernel (){
#--------------------------------------------------------------------------------------------------------------------------------
# Compile kernel
#--------------------------------------------------------------------------------------------------------------------------------
echo -e "[\e[0;32m ok \x1B[0m] Compiling kernel"
if [ -d "$DEST/$LINUXSOURCE" ]; then 

# add small TFT display support  
if [[ "$FBTFT" = "yes" && $BRANCH != "next" ]]; then add_fb_tft ; fi

cd $DEST/$LINUXSOURCE
# delete previous creations
if [ "$KERNEL_CLEAN" = "yes" ]; then make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- clean ; fi

# adding custom firmware to kernel source
if [[ -n "$FIRMWARE" ]]; then unzip -o $SRC/lib/$FIRMWARE -d $DEST/$LINUXSOURCE/firmware; fi

# use proven config
cp $SRC/lib/config/$LINUXCONFIG.config $DEST/$LINUXSOURCE/.config
if [ "$KERNEL_CONFIGURE" = "yes" ]; then make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- menuconfig ; fi

# this way of compilation is much faster. We can use multi threading here but not later
make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- all zImage
# make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- 
# produce deb packages: image, headers, firmware, libc
make -j1 deb-pkg KDEB_PKGVERSION=$REVISION LOCALVERSION="-"$BOARD KBUILD_DEBARCH=armhf ARCH=arm DEBFULLNAME="$MAINTAINER" DEBEMAIL="$MAINTAINERMAIL" CROSS_COMPILE=arm-linux-gnueabihf- 
# ALTERNATIVE DEB_HOST_ARCH=armhf make-kpkg --rootcmd fakeroot --arch arm --cross-compile arm-linux-gnueabihf- --revision=$REVISION --append-to-version=-$BOARD --jobs 3 --overlay-dir $SRC/lib/scripts/build-kernel kernel_image 

# we need a name
CHOOSEN_KERNEL=linux-image-"$VER"-"$CONFIG_LOCALVERSION$BOARD"_"$REVISION"_armhf.deb

# create tar archive of all deb files 
mkdir -p $DEST/output/kernel
cd ..
# add compatible boot loader to the pack
cp $DEST/output/u-boot/$CHOOSEN_UBOOT".deb" .
tar -cPf $DEST"/output/kernel/"$VER"-"$CONFIG_LOCALVERSION$BOARD-$BRANCH".tar" *.deb
rm *.deb
CHOOSEN_KERNEL=$VER"-"$CONFIG_LOCALVERSION$BOARD-$BRANCH".tar"

# go back and patch / unpatch
cd $DEST/$LINUXSOURCE
if [[ "$FBTFT" = "yes" && $BRANCH != "next" ]]; then
# reverse fbtft patch
patch --batch -t -p1 < $SRC/lib/patch/bananafbtft.patch
fi

else
echo "ERROR: Source file $1 does not exists. Check fetch_from_github configuration."
exit
fi
sync
}


create_system_template (){
#--------------------------------------------------------------------------------------------------------------------------------
# Create clean and fresh Debian and Ubuntu image template if it does not exists
#--------------------------------------------------------------------------------------------------------------------------------
if [ ! -f "$DEST/output/rootfs/$RELEASE.raw.gz" ]; then
echo -e "[\e[0;32m ok \x1B[0m] Debootstrap $RELEASE to image template"
cd $DEST/output

# create needed directories and mount image to next free loop device
mkdir -p $DEST/output/rootfs $DEST/output/sdcard/ $DEST/output/kernel

# create image file
dd if=/dev/zero of=$DEST/output/rootfs/$RELEASE.raw bs=1M count=$SDSIZE status=noxfer

# find first avaliable free device
LOOP=$(losetup -f)

# mount image as block device
losetup $LOOP $DEST/output/rootfs/$RELEASE.raw

sync

# create one partition starting at 2048 which is default
echo "------ Partitioning and mounting file-system."
parted -s $LOOP -- mklabel msdos
parted -s $LOOP -- mkpart primary ext4  2048s -1s
partprobe $LOOP 
losetup -d $LOOP
sleep 2

# 2048 (start) x 512 (block size) = where to mount partition
losetup -o 1048576 $LOOP $DEST/output/rootfs/$RELEASE.raw

# create filesystem
mkfs.ext4 $LOOP

# tune filesystem
tune2fs -o journal_data_writeback $LOOP

# mount image to already prepared mount point
mount -t ext4 $LOOP $DEST/output/sdcard/

# debootstrap base system
debootstrap --include=openssh-server,debconf-utils --arch=armhf --foreign $RELEASE $DEST/output/sdcard/ 

# we need emulator for second stage
cp /usr/bin/qemu-arm-static $DEST/output/sdcard/usr/bin/

# enable arm binary format so that the cross-architecture chroot environment will work
test -e /proc/sys/fs/binfmt_misc/qemu-arm || update-binfmts --enable qemu-arm

# debootstrap second stage
chroot $DEST/output/sdcard /bin/bash -c "/debootstrap/debootstrap --second-stage"

# mount proc, sys and dev
mount -t proc chproc $DEST/output/sdcard/proc
mount -t sysfs chsys $DEST/output/sdcard/sys
mount -t devtmpfs chdev $DEST/output/sdcard/dev || mount --bind /dev $DEST/output/sdcard/dev
mount -t devpts chpts $DEST/output/sdcard/dev/pts

# choose proper apt list
cp $SRC/lib/config/sources.list.$RELEASE $DEST/output/sdcard/etc/apt/sources.list

# update and upgrade
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/output/sdcard /bin/bash -c "apt-get -y update"

# install aditional packages
PAKETKI="alsa-utils automake bash-completion bc bridge-utils bluez build-essential cmake cpufrequtils curl device-tree-compiler dosfstools evtest figlet fbset fping git haveged hddtemp hdparm hostapd htop i2c-tools ifenslave-2.6 iperf ir-keytable iotop iw less libbluetooth-dev libbluetooth3 libtool libwrap0-dev libfuse2 libssl-dev lirc lsof makedev module-init-tools mtp-tools nano ntfs-3g ntp parted pkg-config pciutils pv python-smbus rfkill rsync screen stress sudo sysfsutils toilet u-boot-tools unattended-upgrades unzip usbutils vlan wireless-tools wget wpasupplicant"

# generate locales and install packets
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/output/sdcard /bin/bash -c "apt-get -y -qq install locales"
sed -i "s/^# $DEST_LANG/$DEST_LANG/" $DEST/output/sdcard/etc/locale.gen
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/output/sdcard /bin/bash -c "locale-gen $DEST_LANG"
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/output/sdcard /bin/bash -c "export LANG=$DEST_LANG LANGUAGE=$DEST_LANG DEBIAN_FRONTEND=noninteractive"
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/output/sdcard /bin/bash -c "update-locale LANG=$DEST_LANG LANGUAGE=$DEST_LANG LC_MESSAGES=POSIX"
chroot $DEST/output/sdcard /bin/bash -c "debconf-apt-progress -- apt-get -y install $PAKETKI"

# install console setup separate
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/output/sdcard /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y install console-setup console-data kbd console-common unicode-data"

# configure the system for unattended upgrades
cp $SRC/lib/scripts/50unattended-upgrades $DEST/output/sdcard/etc/apt/apt.conf.d/50unattended-upgrades
cp $SRC/lib/scripts/02periodic $DEST/output/sdcard/etc/apt/apt.conf.d/02periodic
sed -e "s/CODENAME/$RELEASE/g" -i $DEST/output/sdcard/etc/apt/apt.conf.d/50unattended-upgrades

# set up 'apt
cat <<END > $DEST/output/sdcard/etc/apt/apt.conf.d/71-no-recommends
APT::Install-Recommends "0";
APT::Install-Suggests "0";
END

# root-fs modifications
rm 	-f $DEST/output/sdcard/etc/motd
touch $DEST/output/sdcard/etc/motd

echo "------ Closing image"
chroot $DEST/output/sdcard /bin/bash -c "sync"
chroot $DEST/output/sdcard /bin/bash -c "unset DEBIAN_FRONTEND"
sync
sleep 3
# unmount proc, sys and dev from chroot
umount -l $DEST/output/sdcard/dev/pts
umount -l $DEST/output/sdcard/dev
umount -l $DEST/output/sdcard/proc
umount -l $DEST/output/sdcard/sys

# kill process inside
KILLPROC=$(ps -uax | pgrep ntpd |        tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi  
KILLPROC=$(ps -uax | pgrep dbus-daemon | tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi  

umount -l $DEST/output/sdcard/ 
sleep 2
losetup -d $LOOP
rm -rf $DEST/output/sdcard/
gzip $DEST/output/rootfs/$RELEASE.raw
fi
#
}


choosing_kernel (){
#--------------------------------------------------------------------------------------------------------------------------------
# Choose which kernel to use  								            
#--------------------------------------------------------------------------------------------------------------------------------
cd $DEST"/output/kernel/"
if [[ $BRANCH == "next" ]]; then
MYLIST=`for x in $(ls -1 *next*.tar); do echo $x " -"; done`
else
MYLIST=`for x in $(ls -1 *.tar | grep -v next); do echo $x " -"; done`
fi
#MYLIST=`for x in $(ls -1 *.tar); do echo $x " -"; done`
WC=`echo $MYLIST | wc -l`
if [[ $WC -ne 0 ]]; then
    whiptail --title "Choose kernel archive" --backtitle "Which kernel do you want to use?" --menu "" 12 60 4 $MYLIST 2>results
fi
CHOOSEN_KERNEL=$(<results)
rm results
}


install_external_applications (){
#--------------------------------------------------------------------------------------------------------------------------------
# Install external applications example
#--------------------------------------------------------------------------------------------------------------------------------
echo -e "[\e[0;32m ok \x1B[0m] Installing external applications"
# USB redirector tools http://www.incentivespro.com
cd $DEST
wget http://www.incentivespro.com/usb-redirector-linux-arm-eabi.tar.gz
tar xfz usb-redirector-linux-arm-eabi.tar.gz
rm usb-redirector-linux-arm-eabi.tar.gz
cd $DEST/usb-redirector-linux-arm-eabi/files/modules/src/tusbd
# patch to work with newer kernels
sed -e "s/f_dentry/f_path.dentry/g" -i usbdcdev.c
make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- KERNELDIR=$DEST/$LINUXSOURCE/
# configure USB redirector
sed -e 's/%INSTALLDIR_TAG%/\/usr\/local/g' $DEST/usb-redirector-linux-arm-eabi/files/rc.usbsrvd > $DEST/usb-redirector-linux-arm-eabi/files/rc.usbsrvd1
sed -e 's/%PIDFILE_TAG%/\/var\/run\/usbsrvd.pid/g' $DEST/usb-redirector-linux-arm-eabi/files/rc.usbsrvd1 > $DEST/usb-redirector-linux-arm-eabi/files/rc.usbsrvd
sed -e 's/%STUBNAME_TAG%/tusbd/g' $DEST/usb-redirector-linux-arm-eabi/files/rc.usbsrvd > $DEST/usb-redirector-linux-arm-eabi/files/rc.usbsrvd1
sed -e 's/%DAEMONNAME_TAG%/usbsrvd/g' $DEST/usb-redirector-linux-arm-eabi/files/rc.usbsrvd1 > $DEST/usb-redirector-linux-arm-eabi/files/rc.usbsrvd
chmod +x $DEST/usb-redirector-linux-arm-eabi/files/rc.usbsrvd
# copy to root
cp $DEST/usb-redirector-linux-arm-eabi/files/usb* $DEST/output/sdcard/usr/local/bin/ 
cp $DEST/usb-redirector-linux-arm-eabi/files/modules/src/tusbd/tusbd.ko $DEST/output/sdcard/usr/local/bin/ 
cp $DEST/usb-redirector-linux-arm-eabi/files/rc.usbsrvd $DEST/output/sdcard/etc/init.d/
# not started by default ----- update.rc rc.usbsrvd defaults
# chroot $DEST/output/sdcard /bin/bash -c "update-rc.d rc.usbsrvd defaults"


# some aditional stuff. Some driver as example
if [[ -n "$MISC3_DIR" ]]; then
	# https://github.com/pvaret/rtl8192cu-fixes
	cd $DEST/$MISC3_DIR
	#git checkout 0ea77e747df7d7e47e02638a2ee82ad3d1563199
	make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- clean >/dev/null 2>&1
	make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- KSRC=$DEST/$LINUXSOURCE/
	cp *.ko $DEST/output/sdcard/usr/local/bin
	#cp blacklist*.conf $DEST/output/sdcard/etc/modprobe.d/
fi

# MISC4 = NOTRO DRIVERS / special handling
# MISC5 = sunxu display control

if [[ -n "$MISC5_DIR" && $BRANCH != "next" ]]; then
	cd $DEST/$MISC5_DIR
	cp $DEST/$LINUXSOURCE/include/video/sunxi_disp_ioctl.h .
	make clean >/dev/null 2>&1
	make ARCH=arm CC=arm-linux-gnueabihf-gcc KSRC=$DEST/$LINUXSOURCE/
	install -m 755 a10disp $DEST/output/sdcard/usr/local/bin
fi

}


fingerprint_image (){
#--------------------------------------------------------------------------------------------------------------------------------
# Saving build summary to the image 							            
#--------------------------------------------------------------------------------------------------------------------------------
echo "------ Saving build summary to the image"
echo $1
echo "--------------------------------------------------------------------------------" > $1
echo "" >> $1
echo "" >> $1
echo "" >> $1
echo "Title:			$VERSION (unofficial)" >> $1
echo "Kernel:			Linux $VER" >> $1
now="$(date +'%d.%m.%Y')" >> $1
printf "Build date:		%s\n" "$now" >> $1
echo "Author:			Igor Pecovnik, www.igorpecovnik.com" >> $1
echo "Sources: 		http://github.com/igorpecovnik" >> $1
echo "" >> $1
echo "" >> $1
echo "" >> $1
echo "--------------------------------------------------------------------------------" >> $1
echo "" >> $1
cat $SRC/lib/LICENSE >> $1
echo "" >> $1
echo "--------------------------------------------------------------------------------" >> $1 
}


closing_image (){
#--------------------------------------------------------------------------------------------------------------------------------
# Closing image and clean-up 									            
#--------------------------------------------------------------------------------------------------------------------------------
echo "------ After install"
chroot $DEST/output/sdcard /bin/bash -c "$AFTERINSTALL"
echo "------ Closing image"
chroot $DEST/output/sdcard /bin/bash -c "sync"
sync
sleep 3
# unmount proc, sys and dev from chroot
umount -l $DEST/output/sdcard/dev/pts
umount -l $DEST/output/sdcard/dev
umount -l $DEST/output/sdcard/proc
umount -l $DEST/output/sdcard/sys
umount -l $DEST/output/sdcard/tmp

# let's create nice file name
VERSION=$VERSION" "$VER
VERSION="${VERSION// /_}"
VERSION="${VERSION//$BRANCH/}"
VERSION="${VERSION//__/_}"

# kill process inside
KILLPROC=$(ps -uax | pgrep ntpd |        tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi  
KILLPROC=$(ps -uax | pgrep dbus-daemon | tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi  

# same info outside the image
cp $DEST/output/sdcard/root/readme.txt $DEST/output/
sleep 2
rm $DEST/output/sdcard/usr/bin/qemu-arm-static 
umount -l $DEST/output/sdcard/ 
sleep 2
losetup -d $LOOP
rm -rf $DEST/output/sdcard/

# write bootloader
LOOP=$(losetup -f)
losetup $LOOP $DEST/output/debian_rootfs.raw
DEVICE=$LOOP dpkg -i $DEST"/output/u-boot/"$CHOOSEN_UBOOT".deb"
dpkg -r linux-u-boot-"$VER"-"$BOARD"
# temporal exception / sources not working
if [[ $BOARD == "udoo-neo" ]];then
dd if=$SRC/lib/bin/u-boot-udoo-neo.imx bs=1k seek=1 of=$LOOP
fi
sync
sleep 3
losetup -d $LOOP
sync
sleep 2
mv $DEST/output/debian_rootfs.raw $DEST/output/$VERSION.raw
sync
cd $DEST/output/
cp $SRC/lib/bin/imagewriter.exe .
# sign with PGP
if [[ $GPG_PASS != "" ]] ; then
	echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --batch --yes $VERSION.raw	
	echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --batch --yes imagewriter.exe
	echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --batch --yes readme.txt
fi
zip $VERSION.zip $VERSION.* readme.* imagewriter.*
rm -f $VERSION.raw *.asc imagewriter.* readme.txt
}
