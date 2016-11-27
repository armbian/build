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
	echo "/dev/mmcblk0p1 / $ROOTFS_TYPE defaults 0 1" >> $CACHEDIR/$SDCARD/etc/fstab

	# create modules file
	if [[ $BRANCH == dev && -n $MODULES_DEV ]]; then
		tr ' ' '\n' <<< "$MODULES_DEV" > $CACHEDIR/$SDCARD/etc/modules
	elif [[ $BRANCH == next || $BRANCH == dev ]]; then
		tr ' ' '\n' <<< "$MODULES_NEXT" > $CACHEDIR/$SDCARD/etc/modules
	else
		tr ' ' '\n' <<< "$MODULES" > $CACHEDIR/$SDCARD/etc/modules
	fi

	# create blacklist files
	if [[ $BRANCH == dev && -n $MODULES_BLACKLIST_DEV ]]; then
		tr ' ' '\n' <<< "$MODULES_BLACKLIST_DEV" | sed -e 's/^/blacklist /' > $CACHEDIR/$SDCARD/etc/modprobe.d/${BOARD}.conf
	elif [[ ($BRANCH == next || $BRANCH == dev) && -n $MODULES_BLACKLIST_NEXT ]]; then
		tr ' ' '\n' <<< "$MODULES_BLACKLIST_NEXT" | sed -e 's/^/blacklist /' > $CACHEDIR/$SDCARD/etc/modprobe.d/${BOARD}.conf
	elif [[ $BRANCH == default && -n $MODULES_BLACKLIST ]]; then
		tr ' ' '\n' <<< "$MODULES_BLACKLIST" | sed -e 's/^/blacklist /' > $CACHEDIR/$SDCARD/etc/modprobe.d/${BOARD}.conf
	fi

	# remove default interfaces file if present
	# before installing board support package
	rm -f $CACHEDIR/$SDCARD/etc/network/interfaces

	mkdir -p $CACHEDIR/$SDCARD/selinux

	# console fix due to Debian bug
	sed -e 's/CHARMAP=".*"/CHARMAP="'$CONSOLE_CHAR'"/g' -i $CACHEDIR/$SDCARD/etc/default/console-setup

	# change time zone data
	echo $TZDATA > $CACHEDIR/$SDCARD/etc/timezone
	chroot $CACHEDIR/$SDCARD /bin/bash -c "dpkg-reconfigure -f noninteractive tzdata >/dev/null 2>&1"

	# set root password
	chroot $CACHEDIR/$SDCARD /bin/bash -c "(echo $ROOTPWD;echo $ROOTPWD;) | passwd root >/dev/null 2>&1"
	# force change root password at first login
	chroot $CACHEDIR/$SDCARD /bin/bash -c "chage -d 0 root"

	# tmpfs configuration
	# Takes effect only in Wheezy and Trusty
	if [[ -f $CACHEDIR/$SDCARD/etc/default/tmpfs ]]; then
		sed -e 's/#RAMTMP=no/RAMTMP=yes/g' -i $CACHEDIR/$SDCARD/etc/default/tmpfs
		sed -e 's/#RUN_SIZE=10%/RUN_SIZE=128M/g' -i $CACHEDIR/$SDCARD/etc/default/tmpfs
		sed -e 's/#LOCK_SIZE=/LOCK_SIZE=/g' -i $CACHEDIR/$SDCARD/etc/default/tmpfs
		sed -e 's/#SHM_SIZE=/SHM_SIZE=128M/g' -i $CACHEDIR/$SDCARD/etc/default/tmpfs
		sed -e 's/#TMP_SIZE=/TMP_SIZE=1G/g' -i $CACHEDIR/$SDCARD/etc/default/tmpfs
	fi

	# add custom bashrc loading
	cat <<-EOF >> $CACHEDIR/$SDCARD/etc/bash.bashrc
	if [[ -f /etc/bash.bashrc.custom ]]; then
	    . /etc/bash.bashrc.custom
	fi
	EOF

	# display welcome message at first root login
	touch $CACHEDIR/$SDCARD/root/.not_logged_in_yet

	# NOTE: this needs to be executed before family_tweaks
	local bootscript_src=${BOOTSCRIPT%%:*}
	local bootscript_dst=${BOOTSCRIPT##*:}
	cp $SRC/lib/config/bootscripts/$bootscript_src $CACHEDIR/$SDCARD/boot/$bootscript_dst

	[[ -n $BOOTENV_FILE && -f $SRC/lib/config/bootenv/$BOOTENV_FILE ]] && \
		cp $SRC/lib/config/bootenv/$BOOTENV_FILE $CACHEDIR/$SDCARD/boot/armbianEnv.txt

	# TODO: modify $bootscript_dst or armbianEnv.txt to make NFS boot universal
	# instead of copying sunxi-specific template
	if [[ $ROOTFS_TYPE == nfs ]]; then
		display_alert "Copying NFS boot script template"
		if [[ -f $SRC/userpatches/nfs-boot.cmd ]]; then
			cp $SRC/userpatches/nfs-boot.cmd $CACHEDIR/$SDCARD/boot/boot.cmd
		else
			cp $SRC/lib/scripts/nfs-boot.cmd.template $CACHEDIR/$SDCARD/boot/boot.cmd
		fi
	fi

	# initial date for fake-hwclock
	date -u '+%Y-%m-%d %H:%M:%S' > $CACHEDIR/$SDCARD/etc/fake-hwclock.data

	echo $HOST > $CACHEDIR/$SDCARD/etc/hostname

	# this is needed for ubuntu
	rm $CACHEDIR/$SDCARD/etc/resolv.conf
	echo "nameserver 8.8.8.8" >> $CACHEDIR/$SDCARD/etc/resolv.conf

	# set hostname in hosts file
	cat <<-EOF > $CACHEDIR/$SDCARD/etc/hosts
	127.0.0.1   localhost $HOST
	::1         localhost $HOST ip6-localhost ip6-loopback
	fe00::0     ip6-localnet
	ff00::0     ip6-mcastprefix
	ff02::1     ip6-allnodes
	ff02::2     ip6-allrouters
	EOF

	display_alert "Installing kernel" "$CHOSEN_KERNEL" "info"
	chroot $CACHEDIR/$SDCARD /bin/bash -c "dpkg -i /tmp/debs/${CHOSEN_KERNEL}_${REVISION}_${ARCH}.deb" >> $DEST/debug/install.log 2>&1

	display_alert "Installing u-boot" "$CHOSEN_UBOOT" "info"
	chroot $CACHEDIR/$SDCARD /bin/bash -c "DEVICE=/dev/null dpkg -i /tmp/debs/${CHOSEN_UBOOT}_${REVISION}_${ARCH}.deb" >> $DEST/debug/install.log 2>&1

	display_alert "Installing headers" "${CHOSEN_KERNEL/image/headers}" "info"
	chroot $CACHEDIR/$SDCARD /bin/bash -c "dpkg -i /tmp/debs/${CHOSEN_KERNEL/image/headers}_${REVISION}_${ARCH}.deb" >> $DEST/debug/install.log 2>&1

	# install firmware
	#if [[ -f $CACHEDIR/$SDCARD/tmp/debs/${CHOSEN_KERNEL/image/firmware-image}_${REVISION}_${ARCH}.deb ]]; then
	#	display_alert "Installing firmware" "${CHOSEN_KERNEL/image/firmware-image}" "info"
	#	chroot $CACHEDIR/$SDCARD /bin/bash -c "dpkg -i /tmp/debs/${CHOSEN_KERNEL/image/firmware-image}_${REVISION}_${ARCH}.deb" >> $DEST/debug/install.log 2>&1
	#fi

	if [[ -f $CACHEDIR/$SDCARD/tmp/debs/armbian-firmware_${REVISION}_${ARCH}.deb ]]; then
		display_alert "Installing generic firmware" "armbian-firmware" "info"
		chroot $CACHEDIR/$SDCARD /bin/bash -c "dpkg -i /tmp/debs/armbian-firmware_${REVISION}_${ARCH}.deb" >> $DEST/debug/install.log 2>&1
	fi

	if [[ -f $CACHEDIR/$SDCARD/tmp/debs/${CHOSEN_KERNEL/image/dtb}_${REVISION}_${ARCH}.deb ]]; then
		display_alert "Installing DTB" "${CHOSEN_KERNEL/image/dtb}" "info"
		chroot $CACHEDIR/$SDCARD /bin/bash -c "dpkg -i /tmp/debs/${CHOSEN_KERNEL/image/dtb}_${REVISION}_${ARCH}.deb" >> $DEST/debug/install.log 2>&1
	fi

	# install board support package
	display_alert "Installing board support package" "$BOARD" "info"
	chroot $CACHEDIR/$SDCARD /bin/bash -c "dpkg -i /tmp/debs/$RELEASE/${CHOSEN_ROOTFS}_${REVISION}_${ARCH}.deb" >> $DEST/debug/install.log 2>&1

	# copy boot splash image
	cp $SRC/lib/bin/armbian.bmp $CACHEDIR/$SDCARD/boot/boot.bmp

	# execute $LINUXFAMILY-specific tweaks from $BOARD.conf
	[[ $(type -t family_tweaks) == function ]] && family_tweaks

	# enable firstrun script
	chroot $CACHEDIR/$SDCARD /bin/bash -c "update-rc.d firstrun defaults >/dev/null 2>&1"

	# remove .old on new image
	rm -rf $CACHEDIR/$SDCARD/boot/dtb.old

	# enable verbose kernel messages on first boot
	touch $CACHEDIR/$SDCARD/boot/.verbose

	# copy "first run automated config, optional user configured"
 	cp $SRC/lib/config/armbian_first_run.txt $CACHEDIR/$SDCARD/boot/armbian_first_run.txt
}

install_distribution_specific()
{
	display_alert "Applying distribution specific tweaks for" "$RELEASE" "info"

	case $RELEASE in

	wheezy)
		# add serial console
		echo T0:2345:respawn:/sbin/getty -L $SERIALCON 115200 vt100 >> $CACHEDIR/$SDCARD/etc/inittab

		# don't clear screen on boot console
		sed -e 's/getty 38400 tty1/getty --noclear 38400 tty1/g' -i $CACHEDIR/$SDCARD/etc/inittab

		# disable some getties
		sed -e 's/5:23:respawn/#5:23:respawn/g' -i $CACHEDIR/$SDCARD/etc/inittab
		sed -e 's/6:23:respawn/#6:23:respawn/g' -i $CACHEDIR/$SDCARD/etc/inittab

		# install ramlog
		cp $SRC/lib/bin/ramlog_2.0.0_all.deb $CACHEDIR/$SDCARD/tmp
		chroot $CACHEDIR/$SDCARD /bin/bash -c "dpkg -i /tmp/ramlog_2.0.0_all.deb >/dev/null 2>&1"
		# enabled back at first run. To remove errors
		chroot $CACHEDIR/$SDCARD /bin/bash -c "service ramlog disable >/dev/null 2>&1"
		rm $CACHEDIR/$SDCARD/tmp/ramlog_2.0.0_all.deb
		sed -e 's/TMPFS_RAMFS_SIZE=/TMPFS_RAMFS_SIZE=512m/g' -i $CACHEDIR/$SDCARD/etc/default/ramlog
		sed -e 's/$remote_fs $time/$remote_fs $time ramlog/g' -i $CACHEDIR/$SDCARD/etc/init.d/rsyslog
		sed -e 's/umountnfs $time/umountnfs $time ramlog/g' -i $CACHEDIR/$SDCARD/etc/init.d/rsyslog
		;;

	jessie)
		# enable root login for latest ssh on jessie
		sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' $CACHEDIR/$SDCARD/etc/ssh/sshd_config

		# add serial console
		#cp $SRC/lib/config/ttyS0.conf $CACHEDIR/$SDCARD/etc/init/$SERIALCON.conf
		#sed -e "s/ttyS0/$SERIALCON/g" -i $CACHEDIR/$SDCARD/etc/init/$SERIALCON.conf
		chroot $CACHEDIR/$SDCARD /bin/bash -c "systemctl --no-reload enable serial-getty@$SERIALCON.service >/dev/null 2>&1"
		mkdir -p "$CACHEDIR/$SDCARD/etc/systemd/system/serial-getty@$SERIALCON.service.d"
		printf "[Service]\nExecStart=\nExecStart=-/sbin/agetty -L 115200 %%I $TERM" > "$CACHEDIR/$SDCARD/etc/systemd/system/serial-getty@$SERIALCON.service.d/10-rate.conf"

		# don't clear screen tty1
		mkdir -p "$CACHEDIR/$SDCARD/etc/systemd/system/getty@tty1.service.d/"
		printf "[Service]\nTTYVTDisallocate=no" > "$CACHEDIR/$SDCARD/etc/systemd/system/getty@tty1.service.d/10-noclear.conf"

		# seting timeout
		mkdir -p $CACHEDIR/$SDCARD/etc/systemd/system/systemd-modules-load.service.d/
		printf "[Service]\nTimeoutStopSec=10" > $CACHEDIR/$SDCARD/etc/systemd/system/systemd-modules-load.service.d/10-timeout.conf

		# handle PMU power button
		mkdir -p $CACHEDIR/$SDCARD/etc/udev/rules.d/
		cp $SRC/lib/config/71-axp-power-button.rules $CACHEDIR/$SDCARD/etc/udev/rules.d/
		;;

	trusty)
		# add serial console
		cat <<-EOF > $CACHEDIR/$SDCARD/etc/init/$SERIALCON.conf
		start on stopped rc RUNLEVEL=[2345]
		stop on runlevel [!2345]

		respawn
		exec /sbin/getty --noclear 115200 $SERIALCON
		EOF

		# don't clear screen tty1
		sed -e s,"exec /sbin/getty","exec /sbin/getty --noclear",g -i $CACHEDIR/$SDCARD/etc/init/tty1.conf

		# disable some getties
		rm -f $CACHEDIR/$SDCARD/etc/init/tty5.conf
		rm -f $CACHEDIR/$SDCARD/etc/init/tty6.conf

		# enable root login for latest ssh on trusty
		sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' $CACHEDIR/$SDCARD/etc/ssh/sshd_config

		# remove legal info from Ubuntu
		[[ -f $CACHEDIR/$SDCARD/etc/legal ]] && rm $CACHEDIR/$SDCARD/etc/legal

		# that my custom motd works well
		if [[ -d $CACHEDIR/$SDCARD/etc/update-motd.d ]]; then
			mv $CACHEDIR/$SDCARD/etc/update-motd.d $CACHEDIR/$SDCARD/etc/update-motd.d-backup
		fi

		# remove what's anyway not working
		#chroot $CACHEDIR/$SDCARD /bin/bash -c "apt-get remove --auto-remove ureadahead"
		rm $CACHEDIR/$SDCARD/etc/init/ureadahead*
		rm $CACHEDIR/$SDCARD/etc/init/plymouth*
		;;

	xenial)
		# enable root login for latest ssh on jessie
		sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' $CACHEDIR/$SDCARD/etc/ssh/sshd_config

		# remove legal info from Ubuntu
		[[ -f $CACHEDIR/$SDCARD/etc/legal ]] && rm $CACHEDIR/$SDCARD/etc/legal

		chroot $CACHEDIR/$SDCARD /bin/bash -c "systemctl --no-reload enable serial-getty@$SERIALCON.service >/dev/null 2>&1"

		# Fix for PuTTY/KiTTY & ncurses-based dialogs (i.e. alsamixer) over serial
		# may break other terminals like screen
		#printf "[Service]\nEnvironment=TERM=xterm-256color" > /etc/systemd/system/serial-getty@.service.d/10-term.conf

		# don't clear screen tty1
		mkdir -p "$CACHEDIR/$SDCARD/etc/systemd/system/getty@tty1.service.d/"
		printf "[Service]\nTTYVTDisallocate=no" > "$CACHEDIR/$SDCARD/etc/systemd/system/getty@tty1.service.d/10-noclear.conf"

		# seting timeout
		mkdir -p $CACHEDIR/$SDCARD/etc/systemd/system/systemd-modules-load.service.d/
		printf "[Service]\nTimeoutStopSec=10" > $CACHEDIR/$SDCARD/etc/systemd/system/systemd-modules-load.service.d/10-timeout.conf

		# Fix for haveged service
		mkdir -p -m755 $CACHEDIR/$SDCARD/etc/systemd/system/haveged.service.d
		cat <<-EOF > $CACHEDIR/$SDCARD/etc/systemd/system/haveged.service.d/10-no-new-privileges.conf
		[Service]
		NoNewPrivileges=false
		EOF

		# handle PMU power button
		mkdir -p $CACHEDIR/$SDCARD/etc/udev/rules.d/
		cp $SRC/lib/config/71-axp-power-button.rules $CACHEDIR/$SDCARD/etc/udev/rules.d/

		# disable not working on unneeded services
		# ureadahead needs kernel tracing options that AFAIK are present only in mainline
		chroot $CACHEDIR/$SDCARD /bin/bash -c "systemctl --no-reload mask ureadahead.service >/dev/null 2>&1"
		chroot $CACHEDIR/$SDCARD /bin/bash -c "systemctl --no-reload mask setserial.service etc-setserial.service >/dev/null 2>&1"
		chroot $CACHEDIR/$SDCARD /bin/bash -c "systemctl --no-reload mask ondemand.service >/dev/null 2>&1"
		;;
	esac
}
