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
# Functions:
# install_board_specific
# install_kernel

install_board_specific (){
#---------------------------------------------------------------------------------------------------------------------------------
# Install board common and specific applications
#---------------------------------------------------------------------------------------------------------------------------------

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


	# Lemaker Guitar
	if [[ $BOARD == "guitar" ]] ; then		

		echo "blacklist wlan_8723bs_vq0" > $DEST/cache/sdcard/etc/modprobe.d/blacklist-guitar.conf
		echo "blacklist ctp_gslX680" >> $DEST/cache/sdcard/etc/modprobe.d/blacklist-guitar.conf
		echo "blacklist ctp_gsl3680" >> $DEST/cache/sdcard/etc/modprobe.d/blacklist-guitar.conf
		echo "blacklist gsensor_mir3da" >> $DEST/cache/sdcard/etc/modprobe.d/blacklist-guitar.conf
		echo "blacklist gsensor_stk8313" >> $DEST/cache/sdcard/etc/modprobe.d/blacklist-guitar.conf
		echo "blacklist gsensor_bma222" >> $DEST/cache/sdcard/etc/modprobe.d/blacklist-guitar.conf
		echo "blacklist lightsensor_ltr301" >> $DEST/cache/sdcard/etc/modprobe.d/blacklist-guitar.conf		

	fi

	# Odroid
	if [[ $BOARD == "odroidxu4" ]] ; then
		
		echo "blacklist ina231_sensor" > $DEST/cache/sdcard/etc/modprobe.d/blacklist-odroid.conf
		chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y -qq remove lirc >/dev/null 2>&1"
		
	fi	

	# Armada
	if [[ $BOARD == "armada" ]] ; then
		
		chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y -qq remove lirc linux-sound-base alsa-base alsa-utils bluez>/dev/null 2>&1"
		
	fi	
	
	# Udoo
	if [[ $BOARD == "udoo" ]] ; then		

		chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y -qq remove lirc >/dev/null 2>&1"
		sed 's/wlan0/wlan2/' -i $DEST/cache/sdcard/etc/network/interfaces.default
		sed 's/wlan0/wlan2/' -i $DEST/cache/sdcard/etc/network/interfaces.bonding
		sed 's/wlan0/wlan2/' -i $DEST/cache/sdcard/etc/network/interfaces.hostapd

	fi


	# Udoo neo
	if [[ $BOARD == "udoo-neo" ]] ; then		

		chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y -qq remove lirc"
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

	# remove not needed packages
	chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y -qq autoremove >/dev/null 2>&1"
	
	# enable first run script
	chroot $DEST/cache/sdcard /bin/bash -c "update-rc.d firstrun defaults >/dev/null 2>&1"

	display_alert "Creating boot scripts" "$BOARD" "info"

	rm -rf $DEST/cache/sdcard/boot/dtb.old # remove .old on new image

	if [[ $BOARD == udoo* ]] ; then
		cp $SRC/lib/config/boot-$BOARD.cmd $DEST/cache/sdcard/boot/boot.cmd
	elif [[ $BOARD == cubox-i* ]]; then
		cp $SRC/lib/config/boot-cubox.cmd $DEST/cache/sdcard/boot/boot.cmd
	elif [[ $BOARD == guitar* ]]; then
		cp $SRC/lib/config/boot-guitar.cmd $DEST/cache/sdcard/boot/boot.cmd
	elif [[ $BOARD == armada* ]]; then
		cp $SRC/lib/config/boot-marvell.cmd $DEST/cache/sdcard/boot/boot.cmd
	elif [[ $BOARD == odroid* ]]; then
		cp $SRC/lib/config/boot-odroid.ini $DEST/cache/sdcard/boot/boot.ini	
	else
		cp $SRC/lib/config/boot.cmd $DEST/cache/sdcard/boot/boot.cmd
		# let's prepare for old kernel too
		chroot $DEST/cache/sdcard /bin/bash -c \
		"ln -s /boot/bin/$BOARD.bin /boot/script.bin >/dev/null 2>&1 || cp /boot/bin/$BOARD.bin /boot/script.bin"
	fi

	# if we have a special fat boot partition, alter rootfs=
	if [[ "$BOOTSIZE" -gt "0" ]]; then
		display_alert "Adjusting boot scripts" "$BOARD" "info"
		[[ -f "$DEST/cache/sdcard/boot/boot.cmd" ]] && sed -e 's/p1 /p2 /g' -i $DEST/cache/sdcard/boot/boot.cmd	
		echo "/dev/mmcblk0p1        /boot   vfat    defaults        0       0" >> $DEST/cache/sdcard/etc/fstab
	fi

	# convert to uboot compatible script
	[[ -f "$DEST/cache/sdcard/boot/boot.cmd" ]] && \
	mkimage -C none -A arm -T script -d $DEST/cache/sdcard/boot/boot.cmd $DEST/cache/sdcard/boot/boot.scr >> /dev/null

	# initial date for fake-hwclock
	date -u '+%Y-%m-%d %H:%M:%S' > $DEST/cache/sdcard/etc/fake-hwclock.data
}


install_kernel (){
#--------------------------------------------------------------------------------------------------------------------------------
# Install kernel to prepared root file-system
#--------------------------------------------------------------------------------------------------------------------------------

	display_alert "Install kernel" "$CHOOSEN_KERNEL" "info"

	# configure MIN / MAX speed for cpufrequtils
	echo "ENABLE=true" > $DEST/cache/sdcard/etc/default/cpufrequtils
	echo "MIN_SPEED=$CPUMIN" >> $DEST/cache/sdcard/etc/default/cpufrequtils
	echo "MAX_SPEED=$CPUMAX" >> $DEST/cache/sdcard/etc/default/cpufrequtils	
	echo "GOVERNOR=$GOVERNOR" >> $DEST/cache/sdcard/etc/default/cpufrequtils
	
	# set hostname 
	echo $HOST > $DEST/cache/sdcard/etc/hostname

	# this is needed for ubuntu
	rm $DEST/cache/sdcard/etc/resolv.conf
	echo "nameserver 8.8.8.8" >> $DEST/cache/sdcard/etc/resolv.conf

	# set hostname in hosts file
	echo "127.0.0.1   localhost $HOST" > $DEST/cache/sdcard/etc/hosts
	echo "::1         localhost $HOST ip6-localhost ip6-loopback" >> $DEST/cache/sdcard/etc/hosts
	echo "fe00::0     ip6-localnet" >> $DEST/cache/sdcard/etc/hosts
	echo "ff00::0     ip6-mcastprefix" >> $DEST/cache/sdcard/etc/hosts
	echo "ff02::1     ip6-allnodes" >> $DEST/cache/sdcard/etc/hosts
	echo "ff02::2     ip6-allrouters" >> $DEST/cache/sdcard/etc/hosts

	# create modules file
	IFS=" "
	if [[ $BRANCH == *next* || $BRANCH == *dev* ]];then
		for word in $MODULES_NEXT; do 
			echo $word >> $DEST/cache/sdcard/etc/modules; 
		done
	else
		for word in $MODULES; do 
			echo $word >> $DEST/cache/sdcard/etc/modules; 
		done
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
	#cd $DEST/cache/sdcard/usr/src/$HEADERS_DIR

	#if [ ! -f $DEST/cache/building/$HEADERS_CACHE.tgz ]; then		
	#	chroot $DEST/cache/sdcard /bin/bash -c "cd /usr/src/$HEADERS_DIR && make headers_check; make headers_install ; make scripts" \
	#	| dialog --progressbox "Compile kernel headers scripts ..." 20 70
	#	rm -rf $DEST/cache/building/repack
	#	mkdir -p $DEST/cache/building -p $DEST/cache/building/repack/usr/src/$HEADERS_DIR -p $DEST/cache/building/repack/DEBIAN
	#	dpkg-deb -x $DEST/debs/$HEADERS_TMP $DEST/cache/building/repack
	#	dpkg-deb -e $DEST/debs/$HEADERS_TMP $DEST/cache/building/repack/DEBIAN
	#	cp -R . $DEST/cache/building/repack/usr/src/$HEADERS_DIR
	#	dpkg-deb -b $DEST/cache/building/repack $DEST/debs
	#	rm -rf $DEST/cache/building/repack
	#	tar cpf - .	| pigz > $DEST/cache/building/$HEADERS_CACHE".tgz"
	#else
	#	pigz -dc $DEST/cache/building/$HEADERS_CACHE".tgz" | tar xpf -		
	#fi
		
	# copy boot splash image
	cp $SRC/lib/bin/armbian.bmp $DEST/cache/sdcard/boot/boot.bmp
	
	# add our linux firmwares to cache image
	unzip -q $SRC/lib/bin/linux-firmware.zip -d $DEST/cache/sdcard/lib/firmware
}