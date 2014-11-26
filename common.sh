#!/bin/bash
#
# Created by Igor Pecovnik, www.igorpecovnik.com
#
# Image build functions


download_host_packages (){
#--------------------------------------------------------------------------------------------------------------------------------
# Download packages for host - Ubuntu 14.04 recommended                     
#--------------------------------------------------------------------------------------------------------------------------------
echo "Downloading necessary files."
# basic
apt-get -y install debconf-utils
debconf-apt-progress -- apt-get -y install pv bc lzop zip binfmt-support bison build-essential ccache debootstrap flex gawk gcc-arm-linux-gnueabi 
debconf-apt-progress -- apt-get -y install gcc-arm-linux-gnueabihf lvm2 qemu-user-static u-boot-tools uuid-dev zlib1g-dev unzip libncurses5-dev
debconf-apt-progress -- apt-get -y install libusb-1.0-0-dev parted pkg-config
# for creating PDF documentation
# debconf-apt-progress -- apt-get -y install pandoc nbibtex texlive-latex-base texlive-latex-recommended texlive-latex-extra preview-latex-style 
# debconf-apt-progress -- apt-get -y install dvipng texlive-fonts-recommended
echo "Done.";
}


fetch_from_github (){
#--------------------------------------------------------------------------------------------------------------------------------
# Download sources from Github 							                    
#--------------------------------------------------------------------------------------------------------------------------------
echo "------ Downloading $2."
if [ -d "$DEST/$2" ]; then
	cd $DEST/$2
		# some patching for TFT display source
		if [[ $1 == "https://github.com/notro/fbtft" ]]; then git checkout master; fi
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
# sunxi
if [[ $LINUXSOURCE == "linux-sunxi" ]] ; then
	# if the source is already patched for banana, do reverse GMAC patch
	if [ "$(cat arch/arm/kernel/setup.c | grep BANANAPI)" != "" ]; then
		echo "Reversing Banana patch"
		patch --batch -t -p1 < $SRC/lib/patch/bananagmac.patch
	fi
	#
	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/gpio.patch | grep previ)" == "" ]; then
		patch --batch -f -p1 < $SRC/lib/patch/gpio.patch
    	fi
	#
    	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/spi.patch | grep previ)" == "" ]; then
		patch --batch -f -p1 < $SRC/lib/patch/spi.patch
    	fi
	#    
	if [[ $BOARD == "bananapi" ]] ; then
        	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/bananagmac.patch | grep previ)" == "" ]; then
        		patch --batch -N -p1 < $SRC/lib/patch/bananagmac.patch
        	fi
    	fi
    	# compile sunxi tools
    	compile_sunxi_tools
fi
# cubox / hummingboard
if [[ $LINUXSOURCE == "linux-cubox-next" ]] ; then
	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/hb-i2c-spi.patch | grep previ)" == "" ]; then
        patch -p1 < $SRC/lib/patch/hb-i2c-spi.patch
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
	make $CTHREADS CROSS_COMPILE=arm-linux-gnueabihf-
else
	make $CTHREADS $BOOTCONFIG CROSS_COMPILE=arm-linux-gnueabihf- 
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
if [[ $BOARD == "bananapi" || $BOARD == "cubietruck" || $BOARD == "cubieboard2" || $BOARD == "lime" || $BOARD == "lime2" ]]; then
	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/bananafbtft.patch | grep previ)" == "" ]; then
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
if [ "$FBTFT" = "yes" ]; then
add_fb_tft 
fi

cd $DEST/$LINUXSOURCE
# delete previous creations
make -s CROSS_COMPILE=arm-linux-gnueabihf- clean

rm -rf output
mkdir -p output/boot output/boot/dtb

# Adding custom firmware to kernel source
if [[ -n "$FIRMWARE" ]]; then unzip -o $SRC/lib/$FIRMWARE -d $DEST/$LINUXSOURCE/firmware; fi

# compile from proven config
cp $SRC/lib/config/$LINUXSOURCE.config $DEST/$LINUXSOURCE/.config
if [ "$KERNEL_CONFIGURE" = "yes" ]; then make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- menuconfig ; fi

# there are more methods of compilation
if [[ $BOARD == "cubox-i" ]]
then
	make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- zImage modules $DTBS LOCALVERSION="$LOCALVERSION"
	make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- INSTALL_MOD_PATH=output modules_install
	make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- INSTALL_HDR_PATH=output/usr headers_install
	cp Module.symvers output/usr/include
	cp arch/arm/boot/zImage output/boot/
	cp arch/arm/boot/dts/*.dtb output/boot
elif [[ $BOARD == *next* ]]
then
	make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- LOADADDR=0x40008000 uImage modules dtbs LOCALVERSION="$LOCALVERSION"
	make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- INSTALL_MOD_PATH=output modules_install
	make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- INSTALL_HDR_PATH=output/usr headers_install
	cp Module.symvers output/usr/include
	cp arch/arm/boot/uImage output/boot/
	cp arch/arm/boot/dts/*.dtb output/boot/dtb
	sed -e "s/WHICH/$DTBS/g" $SRC/lib/config/boot.cmd > /tmp/boot.cmd
	mkimage -C none -A arm -T script -d /tmp/boot.cmd output/boot/boot.scr
else
	make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- uImage modules LOCALVERSION="$LOCALVERSION"
	make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- INSTALL_MOD_PATH=output modules_install
	make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- INSTALL_HDR_PATH=output/usr headers_install
	cp Module.symvers output/usr/include
	cp arch/arm/boot/uImage output/boot/
fi

# add linux firmwares to output image
unzip $SRC/lib/bin/linux-firmware.zip -d output/lib/firmware

if [ "$FBTFT" = "yes" ]; then
# reverse fbtft patch
patch --batch -t -p1 < $SRC/lib/patch/bananafbtft.patch
fi

else
echo "ERROR: Source file $1 does not exists. Check fetch_from_github configuration."
exit
fi
sync
}


packing_kernel (){
#--------------------------------------------------------------------------------------------------------------------------------
# Pack kernel				  							                    
#--------------------------------------------------------------------------------------------------------------------------------
if [ -d "$DEST/$LINUXSOURCE/output/lib/modules/$VER$LOCALVERSION" ]; then 
cd "$DEST/$LINUXSOURCE/output/lib/modules/$VER$LOCALVERSION"
# correct link
rm build source
ln -s /usr/include/ build
ln -s /usr/include/ source
fi
#
cd $DEST/$LINUXSOURCE/output
tar -cPf $DEST"/output/kernel/"$BOARD"_kernel_"$VER"_mod_head_fw.tar" *
cd $DEST/output/kernel
md5sum "$BOARD"_kernel_"$VER"_mod_head_fw.tar > "$BOARD"_kernel_"$VER"_mod_head_fw.md5
zip "$BOARD"_kernel_"$VER"_mod_head_fw.zip "$BOARD"_kernel_"$VER"_mod_head_fw.*
sync
CHOOSEN_KERNEL="$BOARD"_kernel_"$VER"_mod_head_fw.tar
}


creating_image (){
#--------------------------------------------------------------------------------------------------------------------------------
# Create and mount SD image	  							                    
#--------------------------------------------------------------------------------------------------------------------------------
# check if previously build kernel file exits

if [ ! -f "$DEST/output/kernel/"$CHOOSEN_KERNEL ]; then 
	echo "Previously compiled kernel does not exits. Please choose compile=yes in configuration and run again!"
	exit 
fi
echo "------ Creating SD Images"
cd $DEST/output
# create 1G image and mount image to next free loop device
dd if=/dev/zero of=debian_rootfs.raw bs=1M count=$SDSIZE status=noxfer
LOOP=$(losetup -f)
losetup $LOOP debian_rootfs.raw
sync
echo "------ Partitioning, writing boot loader and mounting file-system."
# create one partition starting at 2048 which is default
parted -s $LOOP -- mklabel msdos
parted -s $LOOP -- mkpart primary ext4  2048s -1s
partprobe $LOOP
echo "------ Writing boot loader."
if [[ $BOARD == "cubox-i" ]] ; then
	dd if=$DEST/$BOOTSOURCE/SPL of=$LOOP bs=512 seek=2 status=noxfer
	dd if=$DEST/$BOOTSOURCE/u-boot.img of=$LOOP bs=1K seek=42 status=noxfer
else
	dd if=$DEST/$BOOTSOURCE/u-boot-sunxi-with-spl.bin of=$LOOP bs=1024 seek=8 status=noxfer
fi
sync
sleep 3
losetup -d $LOOP
# 2048 (start) x 512 (block size) = where to mount partition
losetup -o 1048576 $LOOP debian_rootfs.raw
# create filesystem
mkfs.ext4 $LOOP
# tune filesystem
tune2fs -o journal_data_writeback $LOOP
# label it
e2label $LOOP "$BOARD"
# create mount point and mount image 
mkdir -p $DEST/output/sdcard/ $DEST/output/kernel
mount -t ext4 $LOOP $DEST/output/sdcard/
}


install_base_debian (){
#--------------------------------------------------------------------------------------------------------------------------------
# Install base Debian	  								                    
#--------------------------------------------------------------------------------------------------------------------------------
echo "------ Install basic filesystem"

# install base system
debootstrap --no-check-gpg --arch=armhf --foreign $RELEASE $DEST/output/sdcard/
# we need emulator
cp /usr/bin/qemu-arm-static $DEST/output/sdcard/usr/bin/
# enable arm binary format so that the cross-architecture chroot environment will work
test -e /proc/sys/fs/binfmt_misc/qemu-arm || update-binfmts --enable qemu-arm
# mount proc inside chroot
mount -t proc chproc $DEST/output/sdcard/proc
# second stage unmounts proc 
chroot $DEST/output/sdcard /bin/bash -c "/debootstrap/debootstrap --second-stage"
# mount proc, sys and dev
mount -t proc chproc $DEST/output/sdcard/proc
mount -t sysfs chsys $DEST/output/sdcard/sys
mount -t devtmpfs chdev $DEST/output/sdcard/dev || mount --bind /dev $DEST/output/sdcard/dev
mount -t devpts chpts $DEST/output/sdcard/dev/pts
# update /etc/issue
#cat <<EOT > $DEST/output/sdcard/etc/issue
#Debian GNU/Linux $VERSION
#
#EOT
# update /etc/motd
rm $DEST/output/sdcard/etc/motd
touch $DEST/output/sdcard/etc/motd
# choose proper apt list
cp $SRC/lib/config/sources.list.$RELEASE $DEST/output/sdcard/etc/apt/sources.list
# update, fix locales
chroot $DEST/output/sdcard /bin/bash -c "apt-get update"
chroot $DEST/output/sdcard /bin/bash -c "apt-get -qq -y install locales makedev"
sed -i "s/^# $DEST_LANG/$DEST_LANG/" $DEST/output/sdcard/etc/locale.gen
chroot $DEST/output/sdcard /bin/bash -c "locale-gen $DEST_LANG"
chroot $DEST/output/sdcard /bin/bash -c "export LANG=$DEST_LANG LANGUAGE=$DEST_LANG DEBIAN_FRONTEND=noninteractive"
chroot $DEST/output/sdcard /bin/bash -c "update-locale LANG=$DEST_LANG LANGUAGE=$DEST_LANG LC_MESSAGES=POSIX"
# set up 'apt
cat <<END > $DEST/output/sdcard/etc/apt/apt.conf.d/71-no-recommends
APT::Install-Recommends "0";
APT::Install-Suggests "0";
END
# script to show (graphical) boot splash
cp $SRC/lib/scripts/bootsplash $DEST/output/sdcard/etc/init.d/bootsplash
cp $SRC/lib/bin/bootsplash.png $DEST/output/sdcard/etc/bootsplash.png
chroot $DEST/output/sdcard /bin/bash -c "chmod +x /etc/init.d/bootsplash"
# chroot $DEST/output/sdcard /bin/bash -c "insserv bootsplash" 
# scripts for autoresize at first boot
cp $SRC/lib/scripts/resize2fs $DEST/output/sdcard/etc/init.d
cp $SRC/lib/scripts/firstrun $DEST/output/sdcard/etc/init.d
chroot $DEST/output/sdcard /bin/bash -c "chmod +x /etc/init.d/firstrun"
chroot $DEST/output/sdcard /bin/bash -c "chmod +x /etc/init.d/resize2fs"
chroot $DEST/output/sdcard /bin/bash -c "insserv firstrun" 
# install custom bashrc
cat $SRC/lib/scripts/bashrc >> $DEST/output/sdcard/etc/bash.bashrc 
# install custom motd / hardware dependent
cp $SRC/lib/scripts/armhwinfo $DEST/output/sdcard/etc/init.d/
chroot $DEST/output/sdcard /bin/bash -c "chmod +x /etc/init.d/armhwinfo"
#chroot $DEST/output/sdcard /bin/bash -c "insserv armhwinfo" 
sed -e s,"# Update motd","service armhwinfo start",g 	-i $DEST/output/sdcard/etc/init.d/motd
sed -e s,"uname -snrvm > /var/run/motd.dynamic","",g  -i $DEST/output/sdcard/etc/init.d/motd
}


install_board_specific (){
#--------------------------------------------------------------------------------------------------------------------------------
# Install board specific applications  					                    
#--------------------------------------------------------------------------------------------------------------------------------
echo "------ Install board specific applications"
if [[ $LOCALVERSION == *sunxi ]] ; then
		# enable serial console (Debian/sysvinit way)
		echo T0:2345:respawn:/sbin/getty -L ttyS0 115200 vt100 >> $DEST/output/sdcard/etc/inittab		
		# alter rc.local
		head -n -1 $DEST/output/sdcard/etc/rc.local > /tmp/out
		echo 'echo 2 > /proc/irq/$(cat /proc/interrupts | grep eth0 | cut -f 1 -d ":" | tr -d " ")/smp_affinity' >> /tmp/out
		#echo 'KILLPROC=$(ps uax | pgrep fbi | tail -1); if [ -n "$KILLPROC" ]; then kill $KILLPROC; fi ' >> /tmp/out     
		echo 'exit 0' >> /tmp/out
		mv /tmp/out $DEST/output/sdcard/etc/rc.local
		chroot $DEST/output/sdcard /bin/bash -c "chmod +x /etc/rc.local"
		if [[ $BOARD != *next* ]] ; then
			# sunxi tools
			cp $DEST/sunxi-tools/fex2bin $DEST/sunxi-tools/bin2fex $DEST/sunxi-tools/nand-part $DEST/output/sdcard/usr/bin/
			# script to install to SATA
			cp $SRC/lib/scripts/sata-install.sh $DEST/output/sdcard/root
		fi
fi

if [[ $BOARD == "bananapi" ]] ; then
		fex2bin $SRC/lib/config/bananapi.fex $DEST/output/sdcard/boot/bananapi.bin
		cp $SRC/lib/config/uEnv.bananapi $DEST/output/sdcard/boot/uEnv.txt
		# script to turn off the LED blinking
		cp $SRC/lib/scripts/disable_led_banana.sh $DEST/output/sdcard/etc/init.d/disable_led_banana.sh
		chroot $DEST/output/sdcard /bin/bash -c "chmod +x /etc/init.d/disable_led_banana.sh"
		chroot $DEST/output/sdcard /bin/bash -c "insserv disable_led_banana.sh"
		# default lirc configuration
		sed -e 's/DEVICE=""/DEVICE="\/dev\/input\/event1"/g' -i $DEST/output/sdcard/etc/lirc/hardware.conf
		sed -e 's/DRIVER="UNCONFIGURED"/DRIVER="devinput"/g' -i $DEST/output/sdcard/etc/lirc/hardware.conf
		cp $SRC/lib/config/lirc.conf.bananapi $DEST/output/sdcard/etc/lirc/lircd.conf
fi

if [[ $BOARD == "lime" || $BOARD == "lime2" ]] ; then
		fex2bin $SRC/lib/config/olimex-$BOARD.fex $DEST/output/sdcard/boot/$BOARD.bin
		cp $SRC/lib/config/uEnv.bananapi $DEST/output/sdcard/boot/uEnv.txt
		sed -i "s/bananapi.bin/$BOARD.bin/" $DEST/output/sdcard/boot/uEnv.txt
		# script to install to NAND
		cp $SRC/lib/scripts/nand-install.sh $DEST/output/sdcard/root
		cp $SRC/lib/bin/nand1-allwinner.tgz $DEST/output/sdcard/root
fi

if [[ $BOARD == "cubietruck" || $BOARD == "cubieboard2" ]] ; then
		fex2bin $SRC/lib/config/cubietruck.fex $DEST/output/sdcard/boot/cubietruck.bin
		fex2bin $SRC/lib/config/cubieboard2.fex $DEST/output/sdcard/boot/cubieboard2.bin
		cp $SRC/lib/config/uEnv.cubietruck $DEST/output/sdcard/boot/uEnv.ct
		cp $SRC/lib/config/uEnv.cubieboard2 $DEST/output/sdcard/boot/uEnv.cb2
		# script to turn off the LED blinking
		cp $SRC/lib/scripts/disable_led.sh $DEST/output/sdcard/etc/init.d/disable_led.sh
		chroot $DEST/output/sdcard /bin/bash -c "chmod +x /etc/init.d/disable_led.sh"
		chroot $DEST/output/sdcard /bin/bash -c "insserv disable_led.sh" 
		# bluetooth device enabler 
		cp $SRC/lib/bin/brcm_patchram_plus $DEST/output/sdcard/usr/local/bin/brcm_patchram_plus
		chroot $DEST/output/sdcard /bin/bash -c "chmod +x /usr/local/bin/brcm_patchram_plus"
		cp $SRC/lib/scripts/brcm40183 $DEST/output/sdcard/etc/default
		cp $SRC/lib/scripts/brcm40183-patch $DEST/output/sdcard/etc/init.d
		chroot $DEST/output/sdcard /bin/bash -c "chmod +x /etc/init.d/brcm40183-patch"
		# disabled by default
		# chroot $DEST/output/sdcard /bin/bash -c "insserv brcm40183-patch" 
		# default lirc configuration
		sed -i '1i sed -i \x27s/DEVICE="\\/dev\\/input.*/DEVICE="\\/dev\\/input\\/\x27$str\x27"/g\x27 /etc/lirc/hardware.conf' $DEST/output/sdcard/etc/lirc/hardware.conf
		sed -i '1i str=$(cat /proc/bus/input/devices | grep "H: Handlers=sysrq rfkill kbd event" | awk \x27{print $(NF)}\x27)' $DEST/output/sdcard/etc/lirc/hardware.conf
		sed -i '1i # Cubietruck automatic lirc device detection by Igor Pecovnik' $DEST/output/sdcard/etc/lirc/hardware.conf
		sed -e 's/DEVICE=""/DEVICE="\/dev\/input\/event1"/g' -i $DEST/output/sdcard/etc/lirc/hardware.conf
		sed -e 's/DRIVER="UNCONFIGURED"/DRIVER="devinput"/g' -i $DEST/output/sdcard/etc/lirc/hardware.conf
		cp $SRC/lib/config/lirc.conf.cubietruck $DEST/output/sdcard/etc/lirc/lircd.conf
		# script to install to NAND
		cp $SRC/lib/scripts/nand-install.sh $DEST/output/sdcard/root
		cp $SRC/lib/bin/nand1-allwinner.tgz $DEST/output/sdcard/root
fi

if [[ $BOARD == "cubox-i" ]] ; then
		cp $SRC/lib/config/uEnv.cubox-i $DEST/output/sdcard/boot/uEnv.txt
		chroot $DEST/output/sdcard /bin/bash -c "chmod 755 /boot/uEnv.txt"
		# enable serial console (Debian/sysvinit way)
		echo T0:2345:respawn:/sbin/getty -L ttymxc0 115200 vt100 >> $DEST/output/sdcard/etc/inittab
		# default lirc configuration 
		sed -e 's/DEVICE=""/DEVICE="\/dev\/lirc0"/g' -i $DEST/output/sdcard/etc/lirc/hardware.conf
		sed -e 's/DRIVER="UNCONFIGURED"/DRIVER="default"/g' -i $DEST/output/sdcard/etc/lirc/hardware.conf
		cp $SRC/lib/config/lirc.conf.cubox-i $DEST/output/sdcard/etc/lirc/lircd.conf
		cp $SRC/lib/bin/brcm_patchram_plus_cubox $DEST/output/sdcard/usr/local/bin/brcm_patchram_plus
		chroot $DEST/output/sdcard /bin/bash -c "chmod +x /usr/local/bin/brcm_patchram_plus"
		cp $SRC/lib/scripts/brcm4330 $DEST/output/sdcard/etc/default
		cp $SRC/lib/scripts/brcm4330-patch $DEST/output/sdcard/etc/init.d
		chroot $DEST/output/sdcard /bin/bash -c "chmod +x /etc/init.d/brcm4330-patch"
		chroot $DEST/output/sdcard /bin/bash -c "insserv brcm4330-patch" 
		# script to install to SATA
		cp $SRC/lib/scripts/sata-install.sh $DEST/output/sdcard/root
		# alter rc.local
		head -n -1 $DEST/output/sdcard/etc/rc.local > /tmp/out
		#echo 'KILLPROC=$(ps uax | pgrep fbi | tail -1); if [ -n "$KILLPROC" ]; then kill $KILLPROC; fi ' >> /tmp/out 
		echo 'exit 0' >> /tmp/out
		mv /tmp/out $DEST/output/sdcard/etc/rc.local
		chroot $DEST/output/sdcard /bin/bash -c "chmod +x /etc/rc.local"
fi
}


install_applications (){
#--------------------------------------------------------------------------------------------------------------------------------
# Install applications  								                    
#--------------------------------------------------------------------------------------------------------------------------------
echo "------ Installing aditional applications"

PAKETKI="alsa-utils bash-completion bc bluetooth bridge-utils build-essential ca-certificates cmake cpufrequtils curl dosfstools evtest fbi fbset figlet fping git haveged hddtemp hdparm hostapd htop i2c-tools ifenslave-2.6 ifupdown iproute iputils-ping iperf ir-keytable isc-dhcp-client iw less libbluetooth-dev libbluetooth3 libc6 libfuse2 libnl-dev libssl-dev lirc lsof makedev module-init-tools ntfs-3g ntp openssh-server parted pciutils procps python-smbus rfkill rsync screen stress sudo sysfsutils toilet u-boot-tools udev unattended-upgrades unzip usbutils wireless-tools wpasupplicant"

# PAKETKI=$PAKETKI" console-setup console-data libnl-3-dev lvm2" # might be added
# some packets are different in jessie
if [ "$RELEASE" = "jessie" ]; then PAKETKI="${PAKETKI//libnl-dev/libnl-3-dev}";PAKETKI=$PAKETKI" busybox-syslogd"; fi

chroot $DEST/output/sdcard /bin/bash -c "apt-get -qq -y install $PAKETKI && apt-get -y clean"

if [ "$RELEASE" = "wheezy" ]; then
# ramlog
cp $SRC/lib/bin/ramlog_2.0.0_all.deb $DEST/output/sdcard/tmp
chroot $DEST/output/sdcard /bin/bash -c "dpkg -i /tmp/ramlog_2.0.0_all.deb"
sed -e 's/TMPFS_RAMFS_SIZE=/TMPFS_RAMFS_SIZE=512m/g' -i $DEST/output/sdcard/etc/default/ramlog
sed -e 's/# Required-Start:    $remote_fs $time/# Required-Start:    $remote_fs $time ramlog/g' -i $DEST/output/sdcard/etc/init.d/rsyslog 
sed -e 's/# Required-Stop:     umountnfs $time/# Required-Stop:     umountnfs $time ramlog/g' -i $DEST/output/sdcard/etc/init.d/rsyslog   
fi

# replace hostapd from testing binary.
cd $DEST/output/sdcard/usr/sbin/
tar xvfz $SRC/lib/bin/hostapd23.tgz
cp $SRC/lib/config/hostapd.conf $DEST/output/sdcard/etc/hostapd.conf
sed -i "s/BOARD/$BOARD/" $DEST/output/sdcard/etc/hostapd.conf
# don't clear screen
sed -e 's/1:2345:respawn:\/sbin\/getty 38400 tty1/1:2345:respawn:\/sbin\/getty --noclear 38400 tty1/g' -i $DEST/output/sdcard/etc/inittab   
# console
chroot $DEST/output/sdcard /bin/bash -c "export TERM=linux" 
# Change Time zone data
echo $TZDATA > $DEST/output/sdcard/etc/timezone
chroot $DEST/output/sdcard /bin/bash -c "dpkg-reconfigure -f noninteractive tzdata"
# configure MIN / MAX Speed for cpufrequtils
sed -e "s/MIN_SPEED=\"0\"/MIN_SPEED=\"$CPUMIN\"/g" -i $DEST/output/sdcard/etc/init.d/cpufrequtils
sed -e "s/MAX_SPEED=\"0\"/MAX_SPEED=\"$CPUMAX\"/g" -i $DEST/output/sdcard/etc/init.d/cpufrequtils
sed -e 's/ondemand/interactive/g' -i $DEST/output/sdcard/etc/init.d/cpufrequtils
# set root password and force password change upon first login
chroot $DEST/output/sdcard /bin/bash -c "(echo $ROOTPWD;echo $ROOTPWD;) | passwd root"  
chroot $DEST/output/sdcard /bin/bash -c "chage -d 0 root" 
if [ "$RELEASE" = "jessie" ]; then
# enable root login for latest ssh on jessie
sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' $DEST/output/sdcard/etc/ssh/sshd_config || fail
fi
# set hostname 
echo $HOST > $DEST/output/sdcard/etc/hostname
# set hostname in hosts file
cat > $DEST/output/sdcard/etc/hosts <<EOT
127.0.0.1   localhost $HOST
::1         localhost $HOST ip6-localhost ip6-loopback
fe00::0     ip6-localnet
ff00::0     ip6-mcastprefix
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOT
# change default I/O scheduler, noop for flash media, deadline for SSD, cfq for mechanical drive
cat <<EOT >> $DEST/output/sdcard/etc/sysfs.conf
block/mmcblk0/queue/scheduler = noop
#block/sda/queue/scheduler = cfq
EOT
# load modules
cp $SRC/lib/config/modules.$BOARD $DEST/output/sdcard/etc/modules
# copy and create symlink to default interfaces configuration
cp $SRC/lib/config/interfaces.* $DEST/output/sdcard/etc/network/
ln -sf interfaces.default $DEST/output/sdcard/etc/network/interfaces
# add noatime to root FS
echo "/dev/mmcblk0p1  /           ext4    defaults,noatime,nodiratime,data=writeback,commit=600,errors=remount-ro        0       0" >> $DEST/output/sdcard/etc/fstab
# Configure The System For unattended upgrades
cp $SRC/lib/scripts/50unattended-upgrades $DEST/output/sdcard/etc/apt/apt.conf.d/50unattended-upgrades
cp $SRC/lib/scripts/50unattended-upgrades $DEST/output/sdcard/etc/apt/apt.conf.d/02periodic
# flash media tunning
sed -e 's/#RAMTMP=no/RAMTMP=yes/g' -i $DEST/output/sdcard/etc/default/tmpfs
sed -e 's/#RUN_SIZE=10%/RUN_SIZE=128M/g' -i $DEST/output/sdcard/etc/default/tmpfs 
sed -e 's/#LOCK_SIZE=/LOCK_SIZE=/g' -i $DEST/output/sdcard/etc/default/tmpfs 
sed -e 's/#SHM_SIZE=/SHM_SIZE=128M/g' -i $DEST/output/sdcard/etc/default/tmpfs 
sed -e 's/#TMP_SIZE=/TMP_SIZE=1G/g' -i $DEST/output/sdcard/etc/default/tmpfs 
# uncompress kernel
cd $DEST/output/sdcard/
tar -xPf $DEST"/output/kernel/"$CHOOSEN_KERNEL
sync
sleep 3
# cleanup
rm -f $DEST/output/*.md5 *.tar
# recreate boot.scr if using kernel for different board. Mainline only
if [[ $BOARD == *next* ]];then
sed -e "s/WHICH/$DTBS/g" $SRC/lib/config/boot.cmd > /tmp/boot.cmd
mkimage -C none -A arm -T script -d /tmp/boot.cmd $DEST/output/sdcard/boot/boot.scr
fi
}


choosing_kernel (){
#--------------------------------------------------------------------------------------------------------------------------------
# Choose which kernel to use  								            
#--------------------------------------------------------------------------------------------------------------------------------
cd $DEST"/output/kernel/"
MYLIST=`for x in $(ls -1 *kernel*.tar); do echo $x " -"; done`
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

# temper binary for USB temp meter
cd $DEST/output/sdcard/usr/local/bin
tar xvfz $SRC/lib/bin/temper.tgz
# some aditional stuff. Some driver as example
if [[ -n "$MISC3_DIR" ]]; then
	# https://github.com/pvaret/rtl8192cu-fixes
	cd $DEST/$MISC3_DIR
	make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- KSRC=$DEST/$LINUXSOURCE/
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
echo "------ Closing image"
chroot $DEST/output/sdcard /bin/bash -c "sync"
sync
sleep 3
# unmount proc, sys and dev from chroot
umount -l $DEST/output/sdcard/dev/pts
umount -l $DEST/output/sdcard/dev
umount -l $DEST/output/sdcard/proc
umount -l $DEST/output/sdcard/sys

# let's create nice file name
VERSION="${VERSION// /_}"

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

# create documentation
#pandoc $SRC/lib/README.md $DEST/documentation/Home.md --standalone -o $DEST/output/$VERSION.pdf -V geometry:"top=2.54cm, bottom=2.54cm, left=3.17cm, right=3.17cm" -V geometry:paperwidth=21cm -V geometry:paperheight=29.7cm
sync
sleep 2
mv $DEST/output/debian_rootfs.raw $DEST/output/$VERSION.raw
cd $DEST/output/
# creating MD5 sum
sync
md5sum $VERSION.raw > $VERSION.md5 
cp $SRC/lib/bin/imagewriter.exe .
md5sum imagewriter.exe > imagewriter.md5
zip $VERSION.zip $VERSION.* readme.txt imagewriter.*
rm $VERSION.raw $VERSION.md5 imagewriter.* readme.txt
}
