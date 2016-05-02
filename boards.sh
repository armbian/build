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
		$CACHEDIR/sdcard/etc/lirc/hardware.conf
		sed -i '1i str=$(cat /proc/bus/input/devices | grep "H: Handlers=sysrq rfkill kbd event" | awk \x27{print $(NF)}\x27)' \
		$CACHEDIR/sdcard/etc/lirc/hardware.conf
		sed -i '1i # Cubietruck automatic lirc device detection by Igor Pecovnik' $CACHEDIR/sdcard/etc/lirc/hardware.conf
		sed -e 's/DEVICE=""/DEVICE="\/dev\/input\/event1"/g' -i $CACHEDIR/sdcard/etc/lirc/hardware.conf
		sed -e 's/DRIVER="UNCONFIGURED"/DRIVER="devinput"/g' -i $CACHEDIR/sdcard/etc/lirc/hardware.conf
		cp $SRC/lib/config/lirc.conf.cubietruck $CACHEDIR/sdcard/etc/lirc/lircd.conf

	fi


	# Lemaker Guitar
	if [[ $BOARD == "guitar" ]] ; then

		echo "blacklist wlan_8723bs_vq0" > $CACHEDIR/sdcard/etc/modprobe.d/blacklist-guitar.conf
		echo "blacklist ctp_gslX680" >> $CACHEDIR/sdcard/etc/modprobe.d/blacklist-guitar.conf
		echo "blacklist ctp_gsl3680" >> $CACHEDIR/sdcard/etc/modprobe.d/blacklist-guitar.conf
		echo "blacklist gsensor_mir3da" >> $CACHEDIR/sdcard/etc/modprobe.d/blacklist-guitar.conf
		echo "blacklist gsensor_stk8313" >> $CACHEDIR/sdcard/etc/modprobe.d/blacklist-guitar.conf
		echo "blacklist gsensor_bma222" >> $CACHEDIR/sdcard/etc/modprobe.d/blacklist-guitar.conf
		echo "blacklist lightsensor_ltr301" >> $CACHEDIR/sdcard/etc/modprobe.d/blacklist-guitar.conf

	fi

	# Odroid
	if [[ $BOARD == "odroidxu4" ]] ; then

		echo "blacklist ina231_sensor" > $CACHEDIR/sdcard/etc/modprobe.d/blacklist-odroid.conf
		chroot $CACHEDIR/sdcard /bin/bash -c "apt-get -y -qq remove --auto-remove lirc >/dev/null 2>&1"

	fi

	if [[ $BOARD == "odroidc2" ]] ; then
		sed -i 's/MODULES=.*/MODULES="meson-ir"/' $CACHEDIR/sdcard/etc/lirc/hardware.conf
		sed -i 's/LOAD_MODULES=.*/LOAD_MODULES="true"/' $CACHEDIR/sdcard/etc/lirc/hardware.conf
		sed -i 's/DEVICE=.*/DEVICE="\/dev\/lirc0"/' $CACHEDIR/sdcard/etc/lirc/hardware.conf
		sed -i 's/LIRCD_ARGS=.*/LIRCD_ARGS="--uinput"/' $CACHEDIR/sdcard/etc/lirc/hardware.conf
		cp $SRC/lib/config/lirc.conf.odroidc2 $CACHEDIR/sdcard/etc/lirc/lircd.conf
	fi
	
	# Armada
	if [[ $BOARD == "armada" ]] ; then
		chroot $CACHEDIR/sdcard /bin/bash -c "apt-get -y -qq remove --auto-remove lirc linux-sound-base alsa-base alsa-utils bluez>/dev/null 2>&1"
	fi

	# Odroid C2
	if [[ $BOARD == "odroidc2" ]] ; then
		install -m 755 $SRC/lib/scripts/c2_init.sh $CACHEDIR/sdcard/etc/
		sed -e 's/exit 0//g' -i $CACHEDIR/sdcard/etc/rc.local
		echo "/etc/c2_init.sh" >> $CACHEDIR/sdcard/etc/rc.local
		echo "exit 0" >> $CACHEDIR/sdcard/etc/rc.local
	fi
	
	# Udoo
	if [[ $BOARD == "udoo" ]] ; then

		chroot $CACHEDIR/sdcard /bin/bash -c "apt-get -y -qq remove --auto-remove lirc >/dev/null 2>&1"
		sed 's/wlan0/wlan2/' -i $CACHEDIR/sdcard/etc/network/interfaces.default
		sed 's/wlan0/wlan2/' -i $CACHEDIR/sdcard/etc/network/interfaces.bonding
		sed 's/wlan0/wlan2/' -i $CACHEDIR/sdcard/etc/network/interfaces.hostapd

	fi


	# Udoo neo
	if [[ $BOARD == "udoo-neo" ]] ; then

		chroot $CACHEDIR/sdcard /bin/bash -c "apt-get -y -qq remove --auto-remove lirc"
		sed 's/wlan0/wlan2/' -i $CACHEDIR/sdcard/etc/network/interfaces.default
		sed 's/wlan0/wlan2/' -i $CACHEDIR/sdcard/etc/network/interfaces.bonding
		sed 's/wlan0/wlan2/' -i $CACHEDIR/sdcard/etc/network/interfaces.hostapd
		# SD card is elsewhere
		sed 's/mmcblk0p1/mmcblk1p1/' -i $CACHEDIR/sdcard/etc/fstab
		# firmware for M4
		mkdir -p $CACHEDIR/sdcard/boot/bin/
		cp $SRC/lib/bin/m4startup.fw* $CACHEDIR/sdcard/boot/bin/
		# fix for BT
		cp $SRC/lib/bin/udoo-neo-debs/udooneo-bluetooth_1.2-1_armhf.deb /tmp
		chroot $CACHEDIR/sdcard /bin/bash -c "dpkg -i /tmp/udooneo-bluetooth_1.2-1_armhf.deb >/dev/null 2>&1"

	fi


	# cubox / hummingboard
	if [[ $BOARD == cubox-i* ]] ; then

		# default lirc configuration
		sed -e 's/DEVICE=""/DEVICE="\/dev\/lirc0"/g' -i $CACHEDIR/sdcard/etc/lirc/hardware.conf
		sed -e 's/DRIVER="UNCONFIGURED"/DRIVER="default"/g' -i $CACHEDIR/sdcard/etc/lirc/hardware.conf
		cp $SRC/lib/config/lirc.conf.cubox-i $CACHEDIR/sdcard/etc/lirc/lircd.conf
		cp $SRC/lib/bin/brcm_patchram_plus_cubox $CACHEDIR/sdcard/usr/local/bin/brcm_patchram_plus
		chroot $CACHEDIR/sdcard /bin/bash -c "chmod +x /usr/local/bin/brcm_patchram_plus"
		cp $SRC/lib/scripts/brcm4330 $CACHEDIR/sdcard/etc/default
		cp $SRC/lib/scripts/brcm4330-patch $CACHEDIR/sdcard/etc/init.d
		chroot $CACHEDIR/sdcard /bin/bash -c "chmod +x /etc/init.d/brcm4330-patch"
		#chroot $CACHEDIR/sdcard /bin/bash -c "LC_ALL=C LANG=C update-rc.d brcm4330-patch defaults>> /dev/null"

	fi

	# install custom root package
	display_alert "Install board support package" "$BOARD" "info"
	chroot $CACHEDIR/sdcard /bin/bash -c "dpkg -i /tmp/$RELEASE/${CHOSEN_ROOTFS}_${REVISION}_${ARCH}.deb > /dev/null"

	# enable first run script
	chroot $CACHEDIR/sdcard /bin/bash -c "update-rc.d firstrun defaults >/dev/null 2>&1"

	display_alert "Creating boot scripts" "$BOARD" "info"

	rm -rf $CACHEDIR/sdcard/boot/dtb.old # remove .old on new image

	if [[ $BOARD == udoo* ]] ; then
		cp $SRC/lib/config/boot-$BOARD.cmd $CACHEDIR/sdcard/boot/boot.cmd
	elif [[ $BOARD == cubox-i* ]]; then
		cp $SRC/lib/config/boot-cubox.cmd $CACHEDIR/sdcard/boot/boot.cmd
	elif [[ $BOARD == guitar* ]]; then
		cp $SRC/lib/config/boot-guitar.cmd $CACHEDIR/sdcard/boot/boot.cmd
	elif [[ $BOARD == roseapple* ]]; then
		cp $SRC/lib/config/boot-roseapple.cmd $CACHEDIR/sdcard/boot/boot.cmd	
	elif [[ $BOARD == armada* ]]; then
		cp $SRC/lib/config/boot-marvell.cmd $CACHEDIR/sdcard/boot/boot.cmd
	elif [[ $BOARD == odroidxu4 ]]; then
		cp $SRC/lib/config/boot-odroid-xu4.ini $CACHEDIR/sdcard/boot/boot.ini
	elif [[ $BOARD == odroidc1 ]]; then
		cp $SRC/lib/config/boot-odroid-c1.ini $CACHEDIR/sdcard/boot/boot.ini
	elif [[ $BOARD == odroidc2 ]]; then
		cp $SRC/lib/config/boot-odroid-c2.ini $CACHEDIR/sdcard/boot/boot.ini
	else
		cp $SRC/lib/config/boot.cmd $CACHEDIR/sdcard/boot/boot.cmd
		# orangepi h3 temp exceptions
		[[ $LINUXFAMILY == "sun8i" ]] && sed -i -e '1s/^/gpio set PL10\ngpio set PG11\nsetenv machid 1029\nsetenv bootm_boot_mode sec\n/' \
			-e 's/\ disp.screen0_output_mode=1920x1080p60//' -e 's/\ hdmi.audio=EDID:0//' $CACHEDIR/sdcard/boot/boot.cmd
		# let's prepare for old kernel too
		#chroot $CACHEDIR/sdcard /bin/bash -c \
		#"ln -s /boot/bin/$BOARD.bin /boot/script.bin >/dev/null 2>&1 || cp /boot/bin/$BOARD.bin /boot/script.bin"
	fi

	# if we have a special fat boot partition, alter rootfs=
	if [[ $BOOTSIZE -gt 0 ]]; then
		display_alert "Adjusting boot scripts" "$BOARD" "info"
		[[ -f $CACHEDIR/sdcard/boot/boot.cmd ]] && sed -e 's/p1 /p2 /g' -i $CACHEDIR/sdcard/boot/boot.cmd
		echo "/dev/mmcblk0p1        /boot   vfat    defaults        0       0" >> $CACHEDIR/sdcard/etc/fstab
	fi

	# convert to uboot compatible script
	[[ -f $CACHEDIR/sdcard/boot/boot.cmd ]] && \
	mkimage -C none -A arm -T script -d $CACHEDIR/sdcard/boot/boot.cmd $CACHEDIR/sdcard/boot/boot.scr >> /dev/null

	# initial date for fake-hwclock
	date -u '+%Y-%m-%d %H:%M:%S' > $CACHEDIR/sdcard/etc/fake-hwclock.data
}


install_kernel (){
#--------------------------------------------------------------------------------------------------------------------------------
# Install kernel to prepared root file-system
#--------------------------------------------------------------------------------------------------------------------------------

	display_alert "Installing packages" "$CHOSEN_KERNEL" "info"

	# configure MIN / MAX speed for cpufrequtils
	echo "ENABLE=true" > $CACHEDIR/sdcard/etc/default/cpufrequtils
	echo "MIN_SPEED=$CPUMIN" >> $CACHEDIR/sdcard/etc/default/cpufrequtils
	echo "MAX_SPEED=$CPUMAX" >> $CACHEDIR/sdcard/etc/default/cpufrequtils
	echo "GOVERNOR=$GOVERNOR" >> $CACHEDIR/sdcard/etc/default/cpufrequtils

	# set hostname
	echo $HOST > $CACHEDIR/sdcard/etc/hostname

	# this is needed for ubuntu
	rm $CACHEDIR/sdcard/etc/resolv.conf
	echo "nameserver 8.8.8.8" >> $CACHEDIR/sdcard/etc/resolv.conf

	# set hostname in hosts file
	echo "127.0.0.1   localhost $HOST" > $CACHEDIR/sdcard/etc/hosts
	echo "::1         localhost $HOST ip6-localhost ip6-loopback" >> $CACHEDIR/sdcard/etc/hosts
	echo "fe00::0     ip6-localnet" >> $CACHEDIR/sdcard/etc/hosts
	echo "ff00::0     ip6-mcastprefix" >> $CACHEDIR/sdcard/etc/hosts
	echo "ff02::1     ip6-allnodes" >> $CACHEDIR/sdcard/etc/hosts
	echo "ff02::2     ip6-allrouters" >> $CACHEDIR/sdcard/etc/hosts

	# create modules file
	if [[ $BRANCH == next || $BRANCH == dev ]]; then
		tr ' ' '\n' <<< "$MODULES_NEXT" >> $CACHEDIR/sdcard/etc/modules
	else
		tr ' ' '\n' <<< "$MODULES" >> $CACHEDIR/sdcard/etc/modules
	fi

	# copy and create symlink to default interfaces configuration
	cp $SRC/lib/config/network/interfaces.* $CACHEDIR/sdcard/etc/network/
	ln -sf interfaces.default $CACHEDIR/sdcard/etc/network/interfaces

	# mount deb storage to tmp
	mount --bind $DEST/debs/ $CACHEDIR/sdcard/tmp

	# extract kernel version
	VER=$(dpkg --info $DEST/debs/${CHOSEN_KERNEL}_${REVISION}_${ARCH}.deb | grep Descr | awk '{print $(NF)}')
	VER="${VER/-$LINUXFAMILY/}"

	# we need package names for dtb, uboot and headers
	DTB_TMP="${CHOSEN_KERNEL/image/dtb}"
	FW_TMP="${CHOSEN_KERNEL/image/firmware-image}"
	HEADERS_TMP="${CHOSEN_KERNEL/image/headers}"

	# install kernel
	chroot $CACHEDIR/sdcard /bin/bash -c "dpkg -i /tmp/${CHOSEN_KERNEL}_${REVISION}_${ARCH}.deb >/dev/null 2>&1"

	# install uboot
	display_alert "Installing u-boot" "$CHOSEN_UBOOT" "info"
	chroot $CACHEDIR/sdcard /bin/bash -c "DEVICE=/dev/null dpkg -i /tmp/${CHOSEN_UBOOT}_${REVISION}_${ARCH}.deb > /dev/null"

	# install headers
	display_alert "Installing headers" "$HEADERS_TMP" "info"
	chroot $CACHEDIR/sdcard /bin/bash -c "dpkg -i /tmp/${HEADERS_TMP}_${REVISION}_${ARCH}.deb > /dev/null"

	# install firmware
	if [[ -f $CACHEDIR/sdcard/tmp/${FW_TMP}_${REVISION}_${ARCH}.deb ]]; then
		display_alert "Installing firmware" "$FW_TMP" "info"
		chroot $CACHEDIR/sdcard /bin/bash -c "dpkg -i /tmp/${FW_TMP}_${REVISION}_${ARCH}.deb > /dev/null"
	fi
	
	# install DTB
	if [[ -f $CACHEDIR/sdcard/tmp/${DTB_TMP}_${REVISION}_${ARCH}.deb ]]; then
		display_alert "Installing DTB" "$DTB_TMP" "info"
		chroot $CACHEDIR/sdcard /bin/bash -c "dpkg -i /tmp/${DTB_TMP}_${REVISION}_${ARCH}.deb > /dev/null"
	fi

	# copy boot splash image
	cp $SRC/lib/bin/armbian.bmp $CACHEDIR/sdcard/boot/boot.bmp

	# add our linux firmwares to cache image
	unzip -q $SRC/lib/bin/linux-firmware.zip -d $CACHEDIR/sdcard/lib/firmware
}
