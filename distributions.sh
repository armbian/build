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
# install_common
# install_distribution_specific

install_common()
{
	display_alert "Applying common tweaks" "" "info"

	# add dummy fstab entry to make mkinitramfs happy
	echo "/dev/mmcblk0p1 / $ROOTFS_TYPE defaults 0 1" >> $CACHEDIR/sdcard/etc/fstab

	# create modules file
	if [[ $BRANCH == dev && -n $MODULES_DEV ]]; then
		tr ' ' '\n' <<< "$MODULES_DEV" > $CACHEDIR/sdcard/etc/modules
	elif [[ $BRANCH == next || $BRANCH == dev ]]; then
		tr ' ' '\n' <<< "$MODULES_NEXT" > $CACHEDIR/sdcard/etc/modules
	else
		tr ' ' '\n' <<< "$MODULES" > $CACHEDIR/sdcard/etc/modules
	fi

	# remove default interfaces file if present
	# before installing board support package
	rm $CACHEDIR/sdcard/etc/network/interfaces

	mkdir -p $CACHEDIR/sdcard/selinux

	# console fix due to Debian bug
	sed -e 's/CHARMAP=".*"/CHARMAP="'$CONSOLE_CHAR'"/g' -i $CACHEDIR/sdcard/etc/default/console-setup

	# change time zone data
	echo $TZDATA > $CACHEDIR/sdcard/etc/timezone
	chroot $CACHEDIR/sdcard /bin/bash -c "dpkg-reconfigure -f noninteractive tzdata >/dev/null 2>&1"

	# set root password
	chroot $CACHEDIR/sdcard /bin/bash -c "(echo $ROOTPWD;echo $ROOTPWD;) | passwd root >/dev/null 2>&1"
	# force change root password at first login
	chroot $CACHEDIR/sdcard /bin/bash -c "chage -d 0 root"

	# tmpfs configuration
	# Takes effect only in Wheezy and Trusty
	if [[ -f $CACHEDIR/sdcard/etc/default/tmpfs ]]; then
		sed -e 's/#RAMTMP=no/RAMTMP=yes/g' -i $CACHEDIR/sdcard/etc/default/tmpfs
		sed -e 's/#RUN_SIZE=10%/RUN_SIZE=128M/g' -i $CACHEDIR/sdcard/etc/default/tmpfs
		sed -e 's/#LOCK_SIZE=/LOCK_SIZE=/g' -i $CACHEDIR/sdcard/etc/default/tmpfs
		sed -e 's/#SHM_SIZE=/SHM_SIZE=128M/g' -i $CACHEDIR/sdcard/etc/default/tmpfs
		sed -e 's/#TMP_SIZE=/TMP_SIZE=1G/g' -i $CACHEDIR/sdcard/etc/default/tmpfs
	fi

	# add custom bashrc loading
	cat <<-EOF >> $CACHEDIR/sdcard/etc/bash.bashrc
	if [[ -f /etc/bash.bashrc.custom ]]; then
	    . /etc/bash.bashrc.custom
	fi
	EOF

	# display welcome message at first root login
	touch $CACHEDIR/sdcard/root/.not_logged_in_yet

	[[ $(type -t install_boot_script) == function ]] && install_boot_script

	# initial date for fake-hwclock
	date -u '+%Y-%m-%d %H:%M:%S' > $CACHEDIR/sdcard/etc/fake-hwclock.data

	echo $HOST > $CACHEDIR/sdcard/etc/hostname

	# this is needed for ubuntu
	rm $CACHEDIR/sdcard/etc/resolv.conf
	echo "nameserver 8.8.8.8" >> $CACHEDIR/sdcard/etc/resolv.conf

	# set hostname in hosts file
	cat <<-EOF > $CACHEDIR/sdcard/etc/hosts
	127.0.0.1   localhost $HOST
	::1         localhost $HOST ip6-localhost ip6-loopback
	fe00::0     ip6-localnet
	ff00::0     ip6-mcastprefix
	ff02::1     ip6-allnodes
	ff02::2     ip6-allrouters
	EOF

	# we need package names for dtb, uboot and headers
	DTB_TMP="${CHOSEN_KERNEL/image/dtb}"
	FW_TMP="${CHOSEN_KERNEL/image/firmware-image}"
	HEADERS_TMP="${CHOSEN_KERNEL/image/headers}"

	display_alert "Installing kernel" "$CHOSEN_KERNEL" "info"
	chroot $CACHEDIR/sdcard /bin/bash -c "dpkg -i /tmp/debs/${CHOSEN_KERNEL}_${REVISION}_${ARCH}.deb" >> $DEST/debug/install.log 2>&1

	display_alert "Installing u-boot" "$CHOSEN_UBOOT" "info"
	chroot $CACHEDIR/sdcard /bin/bash -c "DEVICE=/dev/null dpkg -i /tmp/debs/${CHOSEN_UBOOT}_${REVISION}_${ARCH}.deb" >> $DEST/debug/install.log 2>&1

	display_alert "Installing headers" "$HEADERS_TMP" "info"
	chroot $CACHEDIR/sdcard /bin/bash -c "dpkg -i /tmp/debs/${HEADERS_TMP}_${REVISION}_${ARCH}.deb" >> $DEST/debug/install.log 2>&1
	
	# install firmware
	#if [[ -f $CACHEDIR/sdcard/tmp/debs/${FW_TMP}_${REVISION}_${ARCH}.deb ]]; then
	#	display_alert "Installing firmware" "$FW_TMP" "info"
	#	chroot $CACHEDIR/sdcard /bin/bash -c "dpkg -i /tmp/debs/${FW_TMP}_${REVISION}_${ARCH}.deb" >> $DEST/debug/install.log 2>&1
	#fi

	if [[ -f $CACHEDIR/sdcard/tmp/debs/armbian-firmware_${REVISION}_${ARCH}.deb ]]; then
		display_alert "Installing generic firmware" "armbian-firmware" "info"
		chroot $CACHEDIR/sdcard /bin/bash -c "dpkg -i /tmp/debs/armbian-firmware_${REVISION}_${ARCH}.deb" >> $DEST/debug/install.log 2>&1
	fi

	if [[ -f $CACHEDIR/sdcard/tmp/debs/${DTB_TMP}_${REVISION}_${ARCH}.deb ]]; then
		display_alert "Installing DTB" "$DTB_TMP" "info"
		chroot $CACHEDIR/sdcard /bin/bash -c "dpkg -i /tmp/debs/${DTB_TMP}_${REVISION}_${ARCH}.deb" >> $DEST/debug/install.log 2>&1
	fi

	# install board support package
	display_alert "Installing board support package" "$BOARD" "info"
	chroot $CACHEDIR/sdcard /bin/bash -c "dpkg -i /tmp/debs/$RELEASE/${CHOSEN_ROOTFS}_${REVISION}_${ARCH}.deb" >> $DEST/debug/install.log 2>&1

	# copy boot splash image
	cp $SRC/lib/bin/armbian.bmp $CACHEDIR/sdcard/boot/boot.bmp

	# execute $LINUXFAMILY-specific tweaks from $BOARD.conf
	[[ $(type -t family_tweaks) == function ]] && family_tweaks

	# enable firstrun script
	chroot $CACHEDIR/sdcard /bin/bash -c "update-rc.d firstrun defaults >/dev/null 2>&1"

	# remove .old on new image
	rm -rf $CACHEDIR/sdcard/boot/dtb.old

	# enable verbose kernel messages on first boot
	touch $CACHEDIR/sdcard/boot/.verbose
}

install_distribution_specific()
{
	display_alert "Applying distribution specific tweaks for" "$RELEASE" "info"

	case $RELEASE in

	wheezy)
		# add serial console
		echo T0:2345:respawn:/sbin/getty -L $SERIALCON 115200 vt100 >> $CACHEDIR/sdcard/etc/inittab

		# don't clear screen on boot console
		sed -e 's/getty 38400 tty1/getty --noclear 38400 tty1/g' -i $CACHEDIR/sdcard/etc/inittab

		# disable some getties
		sed -e 's/5:23:respawn/#5:23:respawn/g' -i $CACHEDIR/sdcard/etc/inittab
		sed -e 's/6:23:respawn/#6:23:respawn/g' -i $CACHEDIR/sdcard/etc/inittab

		# install ramlog
		cp $SRC/lib/bin/ramlog_2.0.0_all.deb $CACHEDIR/sdcard/tmp
		chroot $CACHEDIR/sdcard /bin/bash -c "dpkg -i /tmp/ramlog_2.0.0_all.deb >/dev/null 2>&1"
		# enabled back at first run. To remove errors
		chroot $CACHEDIR/sdcard /bin/bash -c "service ramlog disable >/dev/null 2>&1"
		rm $CACHEDIR/sdcard/tmp/ramlog_2.0.0_all.deb
		sed -e 's/TMPFS_RAMFS_SIZE=/TMPFS_RAMFS_SIZE=512m/g' -i $CACHEDIR/sdcard/etc/default/ramlog
		sed -e 's/$remote_fs $time/$remote_fs $time ramlog/g' -i $CACHEDIR/sdcard/etc/init.d/rsyslog
		sed -e 's/umountnfs $time/umountnfs $time ramlog/g' -i $CACHEDIR/sdcard/etc/init.d/rsyslog
		;;

	jessie)
		# enable root login for latest ssh on jessie
		sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' $CACHEDIR/sdcard/etc/ssh/sshd_config

		# add serial console
		#cp $SRC/lib/config/ttyS0.conf $CACHEDIR/sdcard/etc/init/$SERIALCON.conf
		#sed -e "s/ttyS0/$SERIALCON/g" -i $CACHEDIR/sdcard/etc/init/$SERIALCON.conf
		chroot $CACHEDIR/sdcard /bin/bash -c "systemctl --no-reload enable serial-getty@$SERIALCON.service >/dev/null 2>&1"
		mkdir -p "$CACHEDIR/sdcard/etc/systemd/system/serial-getty@$SERIALCON.service.d"
		printf "[Service]\nExecStart=\nExecStart=-/sbin/agetty -L 115200 %%I $TERM" > "$CACHEDIR/sdcard/etc/systemd/system/serial-getty@$SERIALCON.service.d/10-rate.conf"

		# don't clear screen tty1
		mkdir -p "$CACHEDIR/sdcard/etc/systemd/system/getty@tty1.service.d/"
		printf "[Service]\nTTYVTDisallocate=no" > "$CACHEDIR/sdcard/etc/systemd/system/getty@tty1.service.d/10-noclear.conf"

		# seting timeout
		mkdir -p $CACHEDIR/sdcard/etc/systemd/system/systemd-modules-load.service.d/
		printf "[Service]\nTimeoutStopSec=10" > $CACHEDIR/sdcard/etc/systemd/system/systemd-modules-load.service.d/10-timeout.conf

		# handle PMU power button
		mkdir -p $CACHEDIR/sdcard/etc/udev/rules.d/
		cp $SRC/lib/config/71-axp-power-button.rules $CACHEDIR/sdcard/etc/udev/rules.d/
		;;

	trusty)
		# add serial console
		cat <<-EOF > $CACHEDIR/sdcard/etc/init/$SERIALCON.conf
		start on stopped rc RUNLEVEL=[2345]
		stop on runlevel [!2345]

		respawn
		exec /sbin/getty --noclear 115200 $SERIALCON
		EOF

		# don't clear screen tty1
		sed -e s,"exec /sbin/getty","exec /sbin/getty --noclear",g -i $CACHEDIR/sdcard/etc/init/tty1.conf

		# disable some getties
		rm -f $CACHEDIR/sdcard/etc/init/tty5.conf
		rm -f $CACHEDIR/sdcard/etc/init/tty6.conf

		# enable root login for latest ssh on trusty
		sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' $CACHEDIR/sdcard/etc/ssh/sshd_config

		# remove legal info from Ubuntu
		[[ -f $CACHEDIR/sdcard/etc/legal ]] && rm $CACHEDIR/sdcard/etc/legal

		# that my custom motd works well
		if [[ -d $CACHEDIR/sdcard/etc/update-motd.d ]]; then
			mv $CACHEDIR/sdcard/etc/update-motd.d $CACHEDIR/sdcard/etc/update-motd.d-backup
		fi

		# remove what's anyway not working
		#chroot $CACHEDIR/sdcard /bin/bash -c "apt-get remove --auto-remove ureadahead"
		rm $CACHEDIR/sdcard/etc/init/ureadahead*
		rm $CACHEDIR/sdcard/etc/init/plymouth*
		;;

	xenial)
		# enable root login for latest ssh on jessie
		sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' $CACHEDIR/sdcard/etc/ssh/sshd_config

		# remove legal info from Ubuntu
		[[ -f $CACHEDIR/sdcard/etc/legal ]] && rm $CACHEDIR/sdcard/etc/legal

		chroot $CACHEDIR/sdcard /bin/bash -c "systemctl --no-reload enable serial-getty@$SERIALCON.service >/dev/null 2>&1"

		# Fix for PuTTY/KiTTY & ncurses-based dialogs (i.e. alsamixer) over serial
		# may break other terminals like screen
		#printf "[Service]\nEnvironment=TERM=xterm-256color" > /etc/systemd/system/serial-getty@.service.d/10-term.conf

		# don't clear screen tty1
		mkdir -p "$CACHEDIR/sdcard/etc/systemd/system/getty@tty1.service.d/"
		printf "[Service]\nTTYVTDisallocate=no" > "$CACHEDIR/sdcard/etc/systemd/system/getty@tty1.service.d/10-noclear.conf"

		# seting timeout
		mkdir -p $CACHEDIR/sdcard/etc/systemd/system/systemd-modules-load.service.d/
		printf "[Service]\nTimeoutStopSec=10" > $CACHEDIR/sdcard/etc/systemd/system/systemd-modules-load.service.d/10-timeout.conf

		# handle PMU power button
		mkdir -p $CACHEDIR/sdcard/etc/udev/rules.d/
		cp $SRC/lib/config/71-axp-power-button.rules $CACHEDIR/sdcard/etc/udev/rules.d/

		# disable ureadahead
		# needs kernel tracing options that AFAIK are present only in mainline
		chroot $CACHEDIR/sdcard /bin/bash -c "systemctl --no-reload mask ureadahead.service >/dev/null 2>&1"
		chroot $CACHEDIR/sdcard /bin/bash -c "systemctl --no-reload mask setserial.service etc-setserial.service >/dev/null 2>&1"
		;;

	*)
		exit_with_error "Unknown OS release selected"
		;;
	esac
}
