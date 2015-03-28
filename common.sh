#!/bin/bash
#
# Copyright (c) 2014 Igor Pecovnik, igor.pecovnik@gma**.com
#
# www.igorpecovnik.com / images + support
#
# Image build functions


download_host_packages (){
#--------------------------------------------------------------------------------------------------------------------------------
# Download packages for host - Ubuntu 14.04 recommended                     
#--------------------------------------------------------------------------------------------------------------------------------
apt-get -y -qq install debconf-utils
debconf-apt-progress -- apt-get -y install pv bc lzop zip binfmt-support bison build-essential ccache debootstrap flex gawk 
debconf-apt-progress -- apt-get -y install gcc-arm-linux-gnueabihf lvm2 qemu-user-static u-boot-tools uuid-dev zlib1g-dev unzip 
debconf-apt-progress -- apt-get -y install libusb-1.0-0-dev parted pkg-config expect gcc-arm-linux-gnueabi libncurses5-dev
}


grab_kernel_version (){
	#--------------------------------------------------------------------------------------------------------------------------------
	# grab linux kernel version from Makefile
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
echo "------ Downloading $2."
if [ -d "$DEST/$2" ]; then
	cd $DEST/$2
		# some patching for TFT display source and Realtek RT8192CU drivers
		if [[ $1 == "https://github.com/notro/fbtft" || $1 == "https://github.com/dz0ny/rt8192cu" ]]; then git checkout master; fi
	git pull 
	cd $SRC
else
	git clone $1 $DEST/$2	
fi
}


patching_sources(){
#--------------------------------------------------------------------------------------------------------------------------------
# Patching sources											                   
#--------------------------------------------------------------------------------------------------------------------------------
# kernel

cd $DEST/$LINUXSOURCE

# mainline
if [[ $BRANCH == "next" ]] ; then
	# Fix Kernel Tag
	if [[ KERNELTAG == "" ]] ; then
		git checkout master
	else
		git checkout $KERNELTAG
	fi
	# install device tree blobs in separate package, link zImage to kernel image script
	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/packaging-next.patch | grep previ)" == "" ]; then
        patch -p1 < $SRC/lib/patch/packaging-next.patch
    fi
	# add bananapro DTS
	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/add-banana-pro-dts.patch | grep exists)" == "" ]; then
        patch -p1 < $SRC/lib/patch/add-banana-pro-dts.patch
    fi
	# add bananar1 DTS
	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/add-banana-r1-dts.patch | grep exists)" == "" ]; then
        patch -p1 < $SRC/lib/patch/add-banana-r1-dts.patch
    fi
	# add r1 switch driver
	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/bananapi-r1-next.patch | grep previ)" == "" ]; then
        patch -p1 < $SRC/lib/patch/bananapi-r1-next.patch
    fi
	if [[ $BOARD == udoo* ]] ; then
	# fix DTS tree
	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/udoo-dts-fix.patch | grep previ)" == "" ]; then
        patch -p1 < $SRC/lib/patch/udoo-dts-fix.patch
    fi	
	fi
fi

# sunxi 3.4
if [[ $LINUXSOURCE == "linux-sunxi" ]] ; then
	# if the source is already patched for banana, do reverse GMAC patch
	if [ "$(cat arch/arm/kernel/setup.c | grep BANANAPI)" != "" ]; then
		echo "Reversing Banana patch"
		patch --batch -t -p1 < $SRC/lib/patch/bananagmac.patch
	fi
	# deb packaging patch
	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/packaging.patch | grep previ)" == "" ]; then
		patch --batch -f -p1 < $SRC/lib/patch/packaging.patch
    fi	
	# gpio patch
		if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/gpio.patch | grep previ)" == "" ]; then
			patch --batch -f -p1 < $SRC/lib/patch/gpio.patch
	    fi
	# Temperature reading from A20 chip
		if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/a20-temp.patch | grep previ)" == "" ]; then
			patch --batch -f -p1 < $SRC/lib/patch/a20-temp.patch
	    fi
	# SPI functionality
    	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/spi.patch | grep previ)" == "" ]; then
		patch --batch -f -p1 < $SRC/lib/patch/spi.patch
    	fi
	# banana/orange gmac, wireless and 5&7" touchscreen driver is a bit different  
	if [[ $BOARD == "bananapi" || $BOARD == "orangepi" ]] ; then
        	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/bananagmac.patch | grep previ)" == "" ]; then
        		patch --batch -N -p1 < $SRC/lib/patch/bananagmac.patch
        	fi
			if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/wireless-bananapro.patch | grep previ)" == "" ]; then
        		patch --batch -N -p1 < $SRC/lib/patch/wireless-bananapro.patch
        	fi
			if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/banana-ts.patch | grep previ)" == "" ]; then
        		patch --batch -N -p1 < $SRC/lib/patch/banana-ts.patch
        	fi
			if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/banana-ts-extra.patch | grep previ)" == "" ]; then
        		patch --batch -N -p1 < $SRC/lib/patch/banana-ts-extra.patch
        	fi
			if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/bananapi-r1.patch | grep previ)" == "" ]; then
        		patch --batch -N -p1 < $SRC/lib/patch/bananapi-r1.patch
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

if [[ $BOARD == udoo* ]] ; then
	# This enabled boot script loading from ext2 partition which is my default setup
	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/udoo-uboot-fatboot.patch | grep previ)" == "" ]; then
       		patch --batch -N -p1 < $SRC/lib/patch/udoo-uboot-fatboot.patch
	fi
fi
}


compile_uboot (){
#--------------------------------------------------------------------------------------------------------------------------------
# Compile uboot											                   
#--------------------------------------------------------------------------------------------------------------------------------
echo "------ Compiling universal boot loader"
if [ -d "$DEST/$BOOTSOURCE" ]; then
cd $DEST/$BOOTSOURCE
make -s CROSS_COMPILE=arm-linux-gnueabihf- clean
# there are two methods of compilation
if [[ $BOOTCONFIG == *config* ]]
then
	make $CTHREADS $BOOTCONFIG CROSS_COMPILE=arm-linux-gnueabihf-
		if [[ $BRANCH != "next" && $LINUXCONFIG == *sunxi* ]] ; then
			## patch mainline uboot configuration to boot with old kernels
			echo "CONFIG_ARMV7_BOOT_SEC_DEFAULT=y" >> $DEST/$BOOTSOURCE/.config
			echo "CONFIG_ARMV7_BOOT_SEC_DEFAULT=y" >> $DEST/$BOOTSOURCE/spl/.config
			echo "CONFIG_OLD_SUNXI_KERNEL_COMPAT=y" >> $DEST/$BOOTSOURCE/.config
			echo "CONFIG_OLD_SUNXI_KERNEL_COMPAT=y"	>> $DEST/$BOOTSOURCE/spl/.config	
		fi
	make $CTHREADS CROSS_COMPILE=arm-linux-gnueabihf-
else
	make $CTHREADS $BOOTCONFIG CROSS_COMPILE=arm-linux-gnueabihf- 
fi
# create package
mkdir -p $DEST/output/u-boot
#
CHOOSEN_UBOOT="$BOARD"_"$BRANCH"_u-boot_"$VER".tgz
if [[ $BOARD == cubox-i* ]] ; then
	tar cPfz $DEST"/output/u-boot/$CHOOSEN_UBOOT" SPL u-boot.img
elif [[ $BOARD == udoo* ]] ; then
	tar cPfz $DEST"/output/u-boot/$CHOOSEN_UBOOT" u-boot.imx
else
	tar cPfz $DEST"/output/u-boot/$CHOOSEN_UBOOT" u-boot-sunxi-with-spl.bin
fi
#
else
echo "ERROR: Source file $1 does not exists. Check fetch_from_github configuration."
exit
fi
}


compile_sunxi_tools (){
#--------------------------------------------------------------------------------------------------------------------------------
# Compile sunxi_tools									                    
#--------------------------------------------------------------------------------------------------------------------------------
echo "------ Compiling sunxi tools"
cd $DEST/sunxi-tools
# for host
make -s clean && make -s fex2bin && make -s bin2fex
cp fex2bin bin2fex /usr/local/bin/
# for destination
make -s clean && make $CTHREADS 'fex2bin' CC=arm-linux-gnueabihf-gcc
make $CTHREADS 'bin2fex' CC=arm-linux-gnueabihf-gcc && make $CTHREADS 'nand-part' CC=arm-linux-gnueabihf-gcc
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
	git checkout 06f0bba152c036455ae76d26e612ff0e70a83a82
else
	git checkout master
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
echo "------ Compiling kernel"
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


create_debian_template (){
#--------------------------------------------------------------------------------------------------------------------------------
# Create Debian and Ubuntu image template if it does not exists
#--------------------------------------------------------------------------------------------------------------------------------
if [ ! -f "$DEST/output/rootfs/$RELEASE.raw.gz" ]; then
echo "------ Debootstrap $RELEASE to image template"
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

# label it
e2label $LOOP "$BOARD"

# mount image to already prepared mount point
mount -t ext4 $LOOP $DEST/output/sdcard/

# debootstrap base system
debootstrap --include=openssh-server,debconf-utils --arch=armhf --foreign $RELEASE $DEST/output/sdcard/ 
#debootstrap --include=openssh-server,debconf-utils --arch=armhf --foreign $RELEASE $DEST/output/sdcard/ http://ftp.si.debian.org/debian

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

# root-fs modifications
rm 	-f $DEST/output/sdcard/etc/motd
touch $DEST/output/sdcard/etc/motd

# choose proper apt list
cp $SRC/lib/config/sources.list.$RELEASE $DEST/output/sdcard/etc/apt/sources.list

# update and upgrade
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/output/sdcard /bin/bash -c "apt-get -y update"

# install aditional packages
PAKETKI="alsa-utils automake bash-completion bc bridge-utils bluez build-essential cmake cpufrequtils curl dosfstools evtest figlet fping git haveged hddtemp hdparm hostapd htop i2c-tools ifenslave-2.6 iperf ir-keytable iotop iw less libbluetooth-dev libbluetooth3 libtool libwrap0-dev libfuse2 libssl-dev lirc lsof makedev module-init-tools mtp-tools nano ntfs-3g ntp parted pkg-config pciutils pv python-smbus rfkill rsync screen stress sudo sysfsutils toilet u-boot-tools unattended-upgrades unzip usbutils wireless-tools wget wpasupplicant"

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

case $RELEASE in
#--------------------------------------------------------------------------------------------------------------------------------

wheezy)
		# specifics packets
		LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/output/sdcard /bin/bash -c "debconf-apt-progress -- apt-get -y install libnl-dev"
		# add serial console
		echo T0:2345:respawn:/sbin/getty -L ttyS0 115200 vt100 >> $DEST/output/sdcard/etc/inittab		
		# don't clear screen on boot console
		sed -e 's/1:2345:respawn:\/sbin\/getty 38400 tty1/1:2345:respawn:\/sbin\/getty --noclear 38400 tty1/g' -i $DEST/output/sdcard/etc/inittab
		# disable some getties
		sed -e 's/3:23:respawn/#3:23:respawn/g' -i $DEST/output/sdcard/etc/inittab
		sed -e 's/4:23:respawn/#4:23:respawn/g' -i $DEST/output/sdcard/etc/inittab
		sed -e 's/5:23:respawn/#5:23:respawn/g' -i $DEST/output/sdcard/etc/inittab
		sed -e 's/6:23:respawn/#6:23:respawn/g' -i $DEST/output/sdcard/etc/inittab
		# auto upgrading
		sed -e "s/ORIGIN/Debian/g" -i $DEST/output/sdcard/etc/apt/apt.conf.d/50unattended-upgrades
		;;
jessie)
		# add serial console
		cp $SRC/lib/config/ttyS0.conf $DEST/output/sdcard/etc/init/ttyS0.conf
		# specifics packets add and remove
		LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/output/sdcard /bin/bash -c "debconf-apt-progress -- apt-get -y install libnl-3-dev busybox-syslogd software-properties-common python-software-properties"
		LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/output/sdcard /bin/bash -c "apt-get -y remove rsyslog"		
		# don't clear screen tty1
		sed -e s,"TTYVTDisallocate=yes","TTYVTDisallocate=no",g 	-i $DEST/output/sdcard/etc/systemd/system/getty.target.wants/getty@tty1.service
		# enable root login for latest ssh on jessie
		sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' $DEST/output/sdcard/etc/ssh/sshd_config 
		# auto upgrading
		sed -e "s/ORIGIN/Debian/g" -i $DEST/output/sdcard/etc/apt/apt.conf.d/50unattended-upgrades
		;;
trusty)
		# add serial console
		cp $SRC/lib/config/ttyS0.conf $DEST/output/sdcard/etc/init/ttyS0.conf
		# specifics packets add and remove
		LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/output/sdcard /bin/bash -c "debconf-apt-progress -- apt-get -y install libnl-3-dev busybox-syslogd software-properties-common python-software-properties"
		LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/output/sdcard /bin/bash -c "apt-get -y remove rsyslog"		
		# don't clear screen tty1
		sed -e s,"TTYVTDisallocate=yes","TTYVTDisallocate=no",g 	-i $DEST/output/sdcard/etc/systemd/system/getty.target.wants/getty@tty1.service
		# enable root login for latest ssh on trusty
		sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' $DEST/output/sdcard/etc/ssh/sshd_config 		
		# that my startup scripts works well
		if [ ! -f "$DEST/output/sdcard/sbin/insserv" ]; then
			chroot $DEST/output/sdcard /bin/bash -c "ln -s /usr/lib/insserv/insserv /sbin/insserv"
		fi
		# that my custom motd works well
		if [ -d "$DEST/output/sdcard/etc/update-motd.d" ]; then
			chroot $DEST/output/sdcard /bin/bash -c "mv /etc/update-motd.d /etc/update-motd.d-backup"
		fi
		# auto upgrading
		sed -e "s/ORIGIN/Ubuntu/g" -i $DEST/output/sdcard/etc/apt/apt.conf.d/50unattended-upgrades
		# remove what's anyway not working 
		rm $DEST/output/sdcard/etc/init/ureadahead*
		rm $DEST/output/sdcard/etc/init/plymouth*
		;;
*) echo "Relese hasn't been choosen"
exit
;;
esac
#--------------------------------------------------------------------------------------------------------------------------------

# remove what's not needed
chroot $DEST/output/sdcard /bin/bash -c "debconf-apt-progress -- apt-get -y autoremove"

# set up 'apt
cat <<END > $DEST/output/sdcard/etc/apt/apt.conf.d/71-no-recommends
APT::Install-Recommends "0";
APT::Install-Suggests "0";
END

# scripts for autoresize at first boot
cp $SRC/lib/scripts/resize2fs $DEST/output/sdcard/etc/init.d
cp $SRC/lib/scripts/firstrun $DEST/output/sdcard/etc/init.d
chroot $DEST/output/sdcard /bin/bash -c "chmod +x /etc/init.d/firstrun"
chroot $DEST/output/sdcard /bin/bash -c "chmod +x /etc/init.d/resize2fs"
chroot $DEST/output/sdcard /bin/bash -c "insserv firstrun >> /dev/null" 

# install custom bashrc and hardware dependent motd
cat $SRC/lib/scripts/bashrc >> $DEST/output/sdcard/etc/bash.bashrc 
cp $SRC/lib/scripts/armhwinfo $DEST/output/sdcard/etc/init.d/
chroot $DEST/output/sdcard /bin/bash -c "chmod +x /etc/init.d/armhwinfo"
chroot $DEST/output/sdcard /bin/bash -c "insserv armhwinfo >> /dev/null" 

if [ -f "$DEST/output/sdcard/etc/init.d/motd" ]; then
	sed -e s,"# Update motd","insserv armhwinfo >> /dev/null",g 	-i $DEST/output/sdcard/etc/init.d/motd
	sed -e s,"uname -snrvm > /var/run/motd.dynamic","",g  -i $DEST/output/sdcard/etc/init.d/motd
fi

# install ramlog
if [ "$RELEASE" = "wheezy" ]; then
	cp $SRC/lib/bin/ramlog_2.0.0_all.deb $DEST/output/sdcard/tmp
	chroot $DEST/output/sdcard /bin/bash -c "dpkg -i /tmp/ramlog_2.0.0_all.deb"
	rm $DEST/output/sdcard/tmp/ramlog_2.0.0_all.deb
	sed -e 's/TMPFS_RAMFS_SIZE=/TMPFS_RAMFS_SIZE=512m/g' -i $DEST/output/sdcard/etc/default/ramlog
	sed -e 's/# Required-Start:    $remote_fs $time/# Required-Start:    $remote_fs $time ramlog/g' -i $DEST/output/sdcard/etc/init.d/rsyslog 
	sed -e 's/# Required-Stop:     umountnfs $time/# Required-Stop:     umountnfs $time ramlog/g' -i $DEST/output/sdcard/etc/init.d/rsyslog   
fi

# temper binary for USB temp meter
cd $DEST/output/sdcard/usr/local/bin
tar xvfz $SRC/lib/bin/temper.tgz

# replace hostapd from testing binary
cd $DEST/output/sdcard/usr/sbin/
tar xfz $SRC/lib/bin/hostapd24.tgz
cp $SRC/lib/config/hostapd.conf $DEST/output/sdcard/etc/hostapd.conf

# set console
chroot $DEST/output/sdcard /bin/bash -c "export TERM=linux"

# change time zone data
echo $TZDATA > $DEST/output/sdcard/etc/timezone
chroot $DEST/output/sdcard /bin/bash -c "dpkg-reconfigure -f noninteractive tzdata"

# set root password and force password change upon first login
chroot $DEST/output/sdcard /bin/bash -c "(echo $ROOTPWD;echo $ROOTPWD;) | passwd root"  
chroot $DEST/output/sdcard /bin/bash -c "chage -d 0 root" 

# change default I/O scheduler, noop for flash media, deadline for SSD, cfq for mechanical drive
cat <<EOT >> $DEST/output/sdcard/etc/sysfs.conf
block/mmcblk0/queue/scheduler = noop
#block/sda/queue/scheduler = cfq
EOT

# add noatime to root FS
echo "/dev/mmcblk0p1  /           ext4    defaults,noatime,nodiratime,data=writeback,commit=600,errors=remount-ro        0       0" >> $DEST/output/sdcard/etc/fstab


# flash media tunning
if [ -f "$DEST/output/sdcard/etc/default/tmpfs" ]; then
sed -e 's/#RAMTMP=no/RAMTMP=yes/g' -i $DEST/output/sdcard/etc/default/tmpfs
sed -e 's/#RUN_SIZE=10%/RUN_SIZE=128M/g' -i $DEST/output/sdcard/etc/default/tmpfs 
sed -e 's/#LOCK_SIZE=/LOCK_SIZE=/g' -i $DEST/output/sdcard/etc/default/tmpfs 
sed -e 's/#SHM_SIZE=/SHM_SIZE=128M/g' -i $DEST/output/sdcard/etc/default/tmpfs 
sed -e 's/#TMP_SIZE=/TMP_SIZE=1G/g' -i $DEST/output/sdcard/etc/default/tmpfs
fi

# clean deb cache
chroot $DEST/output/sdcard /bin/bash -c "apt-get -y clean"	

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
# Install external applications  								            
#--------------------------------------------------------------------------------------------------------------------------------
echo "------ Installing external applications"
# USB redirector tools http://www.incentivespro.com
cd $DEST
wget http://www.incentivespro.com/usb-redirector-linux-arm-eabi.tar.gz
tar xvfz usb-redirector-linux-arm-eabi.tar.gz
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
	git checkout 0ea77e747df7d7e47e02638a2ee82ad3d1563199
	make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- clean && make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- KSRC=$DEST/$LINUXSOURCE/
	cp *.ko $DEST/output/sdcard/usr/local/bin
	cp blacklist*.conf $DEST/output/sdcard/etc/modprobe.d/
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
cd /tmp
tar xvfz $DEST"/output/u-boot/"$CHOOSEN_UBOOT
if [[ $BOARD == cubox-i* ]] ; then
	dd if=SPL of=$LOOP bs=512 seek=2 status=noxfer
	dd if=u-boot.img of=$LOOP bs=1K seek=42 status=noxfer
elif [[ $BOARD == udoo* ]] ; then
	dd if=u-boot.imx of=$LOOP bs=1024 seek=1 conv=fsync
elif [[ $BOARD == "cubieboard4" ]]
then
	$SRC/lib/bin/host/cubie-fex2bin $SRC/lib/config/cubieboard4.fex /tmp/sys_config.bin
	$SRC/lib/bin/host/cubie-uboot-spl $SRC/lib/bin/cb4-u-boot-spl.bin /tmp/sys_config.bin /tmp/u-boot-spl_with_sys_config.bin
	dd if=/tmp/u-boot-spl_with_sys_config.bin of=$LOOP bs=1024 seek=8 status=noxfer  
	$SRC/lib/bin/host/cubie-uboot $SRC/lib/bin/cb4-u-boot-sun9iw1p1.bin /tmp/sys_config.bin /tmp/u-boot-sun9iw1p1_with_sys_config.bin
	dd if=/tmp/u-boot-sun9iw1p1_with_sys_config.bin of=$LOOP bs=1024 seek=19096 status=noxfer
else
	dd if=u-boot-sunxi-with-spl.bin of=$LOOP bs=1024 seek=8 status=noxfer
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
