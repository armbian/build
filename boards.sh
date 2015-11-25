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


install_board_specific (){
#--------------------------------------------------------------------------------------------------------------------------------
# Install board common and specific applications
#--------------------------------------------------------------------------------------------------------------------------------


# Allwinner's
if [[ $LINUXFAMILY == sun* ]] ; then	
	
	# default lirc configuration
	sed -i '1i sed -i \x27s/DEVICE="\\/dev\\/input.*/DEVICE="\\/dev\\/input\\/\x27$str\x27"/g\x27 /etc/lirc/hardware.conf' \
	$DEST/cache/sdcard/etc/lirc/hardware.conf
	sed -i '1i str=$(cat /proc/bus/input/devices | grep "H: Handlers=sysrq rfkill kbd event" | awk \x27{print $(NF)}\x27)' \
	$DEST/cache/sdcard/etc/lirc/hardware.conf
	sed -i '1i # Cubietruck automatic lirc device detection by Igor Pecovnik' $DEST/cache/sdcard/etc/lirc/hardware.conf
	sed -e 's/DEVICE=""/DEVICE="\/dev\/input\/event1"/g' -i $DEST/cache/sdcard/etc/lirc/hardware.conf
	sed -e 's/DRIVER="UNCONFIGURED"/DRIVER="devinput"/g' -i $DEST/cache/sdcard/etc/lirc/hardware.conf
	cp $SRC/lib/config/lirc.conf.cubietruck $DEST/cache/sdcard/etc/lirc/lircd.conf

fi 


# udoo
if [[ $BOARD == "udoo" ]] ; then		
		if [ -f $DEST/cache/sdcard/etc/inittab ]; then sed -e "s/ttyS0/ttymxc1/g" -i $DEST/cache/sdcard/etc/inittab; fi
		if [ -f $DEST/cache/sdcard/etc/init/ttyS0.conf ]; then 
			mv $DEST/cache/sdcard/etc/init/ttyS0.conf $DEST/cache/sdcard/etc/init/ttymxc1.conf; 
			sed -e "s/ttyS0/ttymxc1/g" -i $DEST/cache/sdcard/etc/init/ttymxc1.conf; 
		fi
		if [ -f $DEST/cache/sdcard/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service ]; then 
			mv $DEST/cache/sdcard/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service  \
			$DEST/cache/sdcard/etc/systemd/system/getty.target.wants/serial-getty@ttymxc1.service
		fi
		chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y -qq remove lirc >/dev/null 2>&1"
		chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y -qq autoremove >/dev/null 2>&1"		
		sed 's/wlan0/wlan2/' -i $DEST/cache/sdcard/etc/network/interfaces.default
		sed 's/wlan0/wlan2/' -i $DEST/cache/sdcard/etc/network/interfaces.bonding
		sed 's/wlan0/wlan2/' -i $DEST/cache/sdcard/etc/network/interfaces.hostapd
		# Udoo doesn't have interactive 		
		sed -e 's/interactive/ondemand/g' -i $DEST/cache/sdcard/etc/init.d/cpufrequtils
fi


# udoo neo
if [[ $BOARD == "udoo-neo" ]] ; then		
		if [ -f $DEST/cache/sdcard/etc/inittab ]; then sed -e "s/ttyS0/ttymxc0/g" -i $DEST/cache/sdcard/etc/inittab; fi
		if [ -f $DEST/cache/sdcard/etc/init/ttyS0.conf ]; then 
			mv $DEST/cache/sdcard/etc/init/ttyS0.conf $DEST/cache/sdcard/etc/init/ttymxc0.conf
			sed -e "s/ttyS0/ttymxc0/g" -i $DEST/cache/sdcard/etc/init/ttymxc0.conf
		fi	
		if [ -f $DEST/cache/sdcard/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service ]; then 
			mv $DEST/cache/sdcard/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service  \
			$DEST/cache/sdcard/etc/systemd/system/getty.target.wants/serial-getty@ttymxc0.service 
		fi
		chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y -qq remove lirc && apt-get -y -qq autoremove"		
		sed 's/wlan0/wlan2/' -i $DEST/cache/sdcard/etc/network/interfaces.default
		sed 's/wlan0/wlan2/' -i $DEST/cache/sdcard/etc/network/interfaces.bonding
		sed 's/wlan0/wlan2/' -i $DEST/cache/sdcard/etc/network/interfaces.hostapd
		# SD card is elsewhere
		sed 's/mmcblk0p1/mmcblk1p1/' -i $DEST/cache/sdcard/etc/fstab
		# firmware for M4
		mkdir -p $DEST/cache/sdcard/boot/bin/
		cp $SRC/lib/bin/m4startup.fw* $DEST/cache/sdcard/boot/bin/
fi


# cubox / hummingboard
if [[ $BOARD == cubox-i* ]] ; then
		if [ -f $DEST/cache/sdcard/etc/inittab ]; then sed -e "s/ttyS0/ttymxc0/g" -i $DEST/cache/sdcard/etc/inittab; fi
		if [ -f $DEST/cache/sdcard/etc/init/ttyS0.conf ]; then 
			mv $DEST/cache/sdcard/etc/init/ttyS0.conf $DEST/cache/sdcard/etc/init/ttymxc0.conf
			sed -e "s/ttyS0/ttymxc0/g" -i $DEST/cache/sdcard/etc/init/ttymxc0.conf
		fi	
		if [ -f $DEST/cache/sdcard/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service ]; then 
			mv $DEST/cache/sdcard/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service  \
			$DEST/cache/sdcard/etc/systemd/system/getty.target.wants/serial-getty@ttymxc0.service 
		fi
		
		# default lirc configuration 
		sed -e 's/DEVICE=""/DEVICE="\/dev\/lirc0"/g' -i $DEST/cache/sdcard/etc/lirc/hardware.conf
		sed -e 's/DRIVER="UNCONFIGURED"/DRIVER="default"/g' -i $DEST/cache/sdcard/etc/lirc/hardware.conf
		cp $SRC/lib/config/lirc.conf.cubox-i $DEST/cache/sdcard/etc/lirc/lircd.conf
		cp $SRC/lib/bin/brcm_patchram_plus_cubox $DEST/cache/sdcard/usr/local/bin/brcm_patchram_plus
		chroot $DEST/cache/sdcard /bin/bash -c "chmod +x /usr/local/bin/brcm_patchram_plus"
		cp $SRC/lib/scripts/brcm4330 $DEST/cache/sdcard/etc/default
		cp $SRC/lib/scripts/brcm4330-patch $DEST/cache/sdcard/etc/init.d
		chroot $DEST/cache/sdcard /bin/bash -c "chmod +x /etc/init.d/brcm4330-patch"
		chroot $DEST/cache/sdcard /bin/bash -c "update-rc.d brcm4330-patch defaults>> /dev/null"
					
fi

# install custom root package 
chroot $DEST/cache/sdcard /bin/bash -c "dpkg -i /tmp/$RELEASE/$CHOOSEN_ROOTFS.deb >/dev/null 2>&1"

# enable first run script
chroot $DEST/cache/sdcard /bin/bash -c "update-rc.d firstrun defaults >/dev/null 2>&1"

display_alert "Creating boot scripts" "$BOARD" "info"

# remove .old on new image
rm -rf $DEST/cache/sdcard/boot/dtb.old
if [[ $BOARD == udoo* ]] ; then
	cp $SRC/lib/config/boot-$BOARD.cmd $DEST/cache/sdcard/boot/boot.cmd
elif [[ $BOARD == cubox-i* ]]; then
	cp $SRC/lib/config/boot-cubox.cmd $DEST/cache/sdcard/boot/boot.cmd
else
	cp $SRC/lib/config/boot.cmd $DEST/cache/sdcard/boot/boot.cmd
	# let's prepare for old kernel too
	chroot $DEST/cache/sdcard /bin/bash -c \
	"ln -s /boot/bin/$BOARD.bin /boot/script.bin >/dev/null 2>&1 || cp /boot/bin/$BOARD.bin /boot/script.bin"
fi

# if we have a special fat boot partition, alter rootfs=
if [ "$BOOTSIZE" -gt "0" ]; then
	display_alert "Adjusting boot scripts" "$BOARD" "info"
	sed -e 's/p1 /p2 /g' -i $DEST/cache/sdcard/boot/boot.cmd	
	echo "/dev/mmcblk0p1        /boot   vfat    defaults        0       0" >> $DEST/cache/sdcard/etc/fstab
fi

# convert to uboot compatible script
mkimage -C none -A arm -T script -d $DEST/cache/sdcard/boot/boot.cmd $DEST/cache/sdcard/boot/boot.scr >> /dev/null
}


install_kernel (){
#--------------------------------------------------------------------------------------------------------------------------------
# Install kernel to prepared root file-system
#--------------------------------------------------------------------------------------------------------------------------------
display_alert "Install kernel" "$CHOOSEN_KERNEL" "info"
# configure MIN / MAX speed for cpufrequtils
sed -e "s/MIN_SPEED=\"0\"/MIN_SPEED=\"$CPUMIN\"/g" -i $DEST/cache/sdcard/etc/init.d/cpufrequtils
sed -e "s/MAX_SPEED=\"0\"/MAX_SPEED=\"$CPUMAX\"/g" -i $DEST/cache/sdcard/etc/init.d/cpufrequtils
# interactive currently available only on 3.4
if [[ $BRANCH != *next* ]];then
	sed -e 's/ondemand/interactive/g' -i $DEST/cache/sdcard/etc/init.d/cpufrequtils
fi
# set hostname 
echo $HOST > $DEST/cache/sdcard/etc/hostname

# this is needed for ubuntu
rm $DEST/cache/sdcard/etc/resolv.conf
echo "nameserver 8.8.8.8" >> $DEST/cache/sdcard/etc/resolv.conf

# set hostname in hosts file
cat > $DEST/cache/sdcard/etc/hosts <<EOT
127.0.0.1   localhost $HOST
::1         localhost $HOST ip6-localhost ip6-loopback
fe00::0     ip6-localnet
ff00::0     ip6-mcastprefix
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOT

# create modules file
IFS=" "
if [[ $BRANCH == *next* ]];then
for word in $MODULES_NEXT; do echo $word >> $DEST/cache/sdcard/etc/modules; done
else
for word in $MODULES; do echo $word >> $DEST/cache/sdcard/etc/modules; done
fi

# copy and create symlink to default interfaces configuration
cp $SRC/lib/config/interfaces.* $DEST/cache/sdcard/etc/network/
ln -sf interfaces.default $DEST/cache/sdcard/etc/network/interfaces

# mount deb storage to tmp
mount --bind $DEST/debs/ $DEST/cache/sdcard/tmp

# extract kernel version
VER=$(dpkg --info $DEST/debs/$CHOOSEN_KERNEL | grep Descr | awk '{print $(NF)}')
HEADERS_DIR="linux-headers-"$VER
VER="${VER/-$LINUXFAMILY/}"

# we need package names for dtb, uboot and headers
UBOOT_TMP="${CHOOSEN_KERNEL/image/u-boot}"
DTB_TMP="${CHOOSEN_KERNEL/image/dtb}"
FW_TMP="${CHOOSEN_KERNEL/image/firmware-image}"
HEADERS_TMP="${CHOOSEN_KERNEL/image/headers}"
HEADERS_CACHE="${CHOOSEN_KERNEL/image/cache}"

# install kernel
chroot $DEST/cache/sdcard /bin/bash -c "dpkg -i /tmp/$CHOOSEN_KERNEL >/dev/null 2>&1"
# install uboot
display_alert "Install u-boot" "$UBOOT_TMP" "info"
chroot $DEST/cache/sdcard /bin/bash -c "dpkg -i /tmp/$UBOOT_TMP >/dev/null 2>&1"
# install headers
display_alert "Install headers" "$HEADERS_TMP" "info"
chroot $DEST/cache/sdcard /bin/bash -c "dpkg -i /tmp/$HEADERS_TMP >/dev/null 2>&1"
# install firmware
display_alert "Install firmware" "$FW_TMP" "info"
chroot $DEST/cache/sdcard /bin/bash -c "dpkg -i /tmp/$FW_TMP >/dev/null 2>&1"
# install DTB
if [ -f $DEST/cache/sdcard/tmp/$DTB_TMP ]; then 
	display_alert "Install DTB" "$DTB_TMP" "info"
	chroot $DEST/cache/sdcard /bin/bash -c "dpkg -i /tmp/$DTB_TMP >/dev/null 2>&1"; 
fi

# recompile headers scripts or use cache if exists 
cd $DEST/cache/sdcard/usr/src/$HEADERS_DIR

if [ ! -f $DEST/cache/building/$HEADERS_CACHE.tgz ]; then
	#display_alert "Compile kernel headers scripts" "$VER" "info"
	chroot $DEST/cache/sdcard /bin/bash -c "cd /usr/src/$HEADERS_DIR && make headers_check; make headers_install ; make scripts" | dialog --progressbox "Compile kernel headers scripts ..." 20 70
	rm -rf $DEST/cache/building/repack
	mkdir -p $DEST/cache/building -p $DEST/cache/building/repack/usr/src/$HEADERS_DIR -p $DEST/cache/building/repack/DEBIAN
	dpkg-deb -x $DEST/debs/$HEADERS_TMP $DEST/cache/building/repack
	dpkg-deb -e $DEST/debs/$HEADERS_TMP $DEST/cache/building/repack/DEBIAN
	cp -R . $DEST/cache/building/repack/usr/src/$HEADERS_DIR
	dpkg-deb -b $DEST/cache/building/repack $DEST/debs
	rm -rf $DEST/cache/building/repack
	tar czpf $DEST/cache/building/$HEADERS_CACHE".tgz" .	
else
	tar xzpf $DEST/cache/building/$HEADERS_CACHE".tgz"
fi



		
# copy boot splash image
cp $SRC/lib/bin/armbian.bmp $DEST/cache/sdcard/boot/boot.bmp
	
# add linux firmwares to cache image
unzip -q $SRC/lib/bin/linux-firmware.zip -d $DEST/cache/sdcard/lib/firmware
}