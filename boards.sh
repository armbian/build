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

	# execute $LINUXFAMILY-specific tweaks from $BOARD.conf
	[[ $(type -t family_tweaks) == function ]] && family_tweaks

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
	elif [[ $BOARD == pine64* ]]; then
		cp $SRC/lib/config/boot-pine64.cmd $CACHEDIR/sdcard/boot/boot.cmd
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

	if [[ $BOARD == cubox-i && $BRANCH == next && -f $CACHEDIR/sdcard/boot/boot.cmd ]] ; then
		sed -e 's/mmcblk0/mmcblk1/g' -i $CACHEDIR/sdcard/boot/boot.cmd
		sed -e 's/console=tty1 //g' -i $CACHEDIR/sdcard/boot/boot.cmd
		sed -e 's/loglevel=1/loglevel=9/g' -i $CACHEDIR/sdcard/boot/boot.cmd
	fi
	
	# convert to uboot compatible script
	[[ -f $CACHEDIR/sdcard/boot/boot.cmd ]] && \
		mkimage -C none -A arm -T script -d $CACHEDIR/sdcard/boot/boot.cmd $CACHEDIR/sdcard/boot/boot.scr >> /dev/null

	# initial date for fake-hwclock
	date -u '+%Y-%m-%d %H:%M:%S' > $CACHEDIR/sdcard/etc/fake-hwclock.data

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
}


install_kernel (){
#--------------------------------------------------------------------------------------------------------------------------------
# Install kernel to prepared root file-system
#--------------------------------------------------------------------------------------------------------------------------------

	display_alert "Installing packages" "$CHOSEN_KERNEL" "info"

	# mount deb storage to tmp
	mount --bind $DEST/debs/ $CACHEDIR/sdcard/tmp

	# install custom root package
	display_alert "Installing board support package" "$BOARD" "info"
	chroot $CACHEDIR/sdcard /bin/bash -c "dpkg -i /tmp/$RELEASE/${CHOSEN_ROOTFS}_${REVISION}_${ARCH}.deb > /dev/null"

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
