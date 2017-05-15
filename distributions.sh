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
# post_debootstrap_tweaks

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
		tr ' ' '\n' <<< "$MODULES_BLACKLIST_DEV" | sed -e 's/^/blacklist /' > $CACHEDIR/$SDCARD/etc/modprobe.d/blacklist-${BOARD}.conf
	elif [[ ($BRANCH == next || $BRANCH == dev) && -n $MODULES_BLACKLIST_NEXT ]]; then
		tr ' ' '\n' <<< "$MODULES_BLACKLIST_NEXT" | sed -e 's/^/blacklist /' > $CACHEDIR/$SDCARD/etc/modprobe.d/blacklist-${BOARD}.conf
	elif [[ $BRANCH == default && -n $MODULES_BLACKLIST ]]; then
		tr ' ' '\n' <<< "$MODULES_BLACKLIST" | sed -e 's/^/blacklist /' > $CACHEDIR/$SDCARD/etc/modprobe.d/blacklist-${BOARD}.conf
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

	[[ -n $OVERLAY_PREFIX && -f $CACHEDIR/$SDCARD/boot/armbianEnv.txt ]] && \
		echo "overlay_prefix=$OVERLAY_PREFIX" >> $CACHEDIR/$SDCARD/boot/armbianEnv.txt

	# initial date for fake-hwclock
	date -u '+%Y-%m-%d %H:%M:%S' > $CACHEDIR/$SDCARD/etc/fake-hwclock.data

	echo $HOST > $CACHEDIR/$SDCARD/etc/hostname

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

	# copy boot splash images
	cp $SRC/lib/bin/splash/armbian-u-boot.bmp $CACHEDIR/$SDCARD/boot/boot.bmp
	cp $SRC/lib/bin/splash/armbian-desktop.png $CACHEDIR/$SDCARD/boot/boot-desktop.png

	# execute $LINUXFAMILY-specific tweaks from $BOARD.conf
	[[ $(type -t family_tweaks) == function ]] && family_tweaks

	install -m 755 $SRC/lib/scripts/resize2fs $CACHEDIR/$SDCARD/etc/init.d/
	install -m 755 $SRC/lib/scripts/firstrun  $CACHEDIR/$SDCARD/etc/init.d/
	install -m 644 $SRC/lib/scripts/resize2fs.service $CACHEDIR/$SDCARD/etc/systemd/system/
	install -m 644 $SRC/lib/scripts/firstrun.service $CACHEDIR/$SDCARD/etc/systemd/system/

	# enable additional services
	chroot $CACHEDIR/$SDCARD /bin/bash -c "systemctl --no-reload enable firstrun.service resize2fs.service armhwinfo.service log2ram.service xdgcache2ram.service >/dev/null 2>&1"

	# copy "first run automated config, optional user configured"
 	cp $SRC/lib/config/armbian_first_run.txt $CACHEDIR/$SDCARD/boot/armbian_first_run.txt

	# switch to beta repository at this stage if building nightly images
	[[ $IMAGE_TYPE == nightly ]] && echo "deb http://beta.armbian.com $RELEASE main utils ${RELEASE}-desktop" > $CACHEDIR/$SDCARD/etc/apt/sources.list.d/armbian.list

	# disable low-level kernel messages for non betas
	if [[ -z $BETA ]]; then
		sed -i "s/^#kernel.printk*/kernel.printk/" $CACHEDIR/$SDCARD/etc/sysctl.conf
	fi

	# enable getty on serial console
	chroot $CACHEDIR/$SDCARD /bin/bash -c "systemctl --no-reload enable serial-getty@$SERIALCON.service >/dev/null 2>&1"

	# don't clear screen tty1
	mkdir -p "$CACHEDIR/$SDCARD/etc/systemd/system/getty@tty1.service.d/"
	printf "[Service]\nTTYVTDisallocate=no" > "$CACHEDIR/$SDCARD/etc/systemd/system/getty@tty1.service.d/10-noclear.conf"

	# reduce modules unload timeout
	mkdir -p $CACHEDIR/$SDCARD/etc/systemd/system/systemd-modules-load.service.d/
	printf "[Service]\nTimeoutStopSec=10" > $CACHEDIR/$SDCARD/etc/systemd/system/systemd-modules-load.service.d/10-timeout.conf

	# handle PMU power button
	mkdir -p $CACHEDIR/$SDCARD/etc/udev/rules.d/
	cp $SRC/lib/config/71-axp-power-button.rules $CACHEDIR/$SDCARD/etc/udev/rules.d/

	[[ $LINUXFAMILY == sun*i ]] && mkdir -p $CACHEDIR/$SDCARD/boot/overlay-user

	# Fix for PuTTY/KiTTY & ncurses-based dialogs (i.e. alsamixer) over serial
	# may break other terminals like screen
	mkdir -p $CACHEDIR/$SDCARD/etc/systemd/system/serial-getty@.service.d/
	printf "[Service]\nEnvironment=TERM=linux" > $CACHEDIR/$SDCARD/etc/systemd/system/serial-getty@.service.d/10-term.conf

	# to prevent creating swap file on NFS (needs specific kernel options)
	# and f2fs/btrfs (not recommended or needs specific kernel options)
	[[ $ROOTFS_TYPE != ext4 ]] && touch $CACHEDIR/$SDCARD/var/swap
}

install_distribution_specific()
{
	display_alert "Applying distribution specific tweaks for" "$RELEASE" "info"
	case $RELEASE in
	jessie)
		# enable root login for latest ssh on jessie
		sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' $CACHEDIR/$SDCARD/etc/ssh/sshd_config

		mkdir -p $CACHEDIR/$SDCARD/etc/NetworkManager/dispatcher.d/
		cat <<-'EOF' > $CACHEDIR/$SDCARD/etc/NetworkManager/dispatcher.d/99disable-power-management
		#!/bin/sh
		case "$2" in
			up) /sbin/iwconfig $1 power off || true ;;
			down) /sbin/iwconfig $1 power on || true ;;
		esac
		EOF
		chmod 755 $CACHEDIR/$SDCARD/etc/NetworkManager/dispatcher.d/99disable-power-management
		;;

	xenial)
		# enable root login for latest ssh on jessie
		sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' $CACHEDIR/$SDCARD/etc/ssh/sshd_config

		# remove legal info from Ubuntu
		[[ -f $CACHEDIR/$SDCARD/etc/legal ]] && rm $CACHEDIR/$SDCARD/etc/legal

		# Fix for haveged service
		mkdir -p -m755 $CACHEDIR/$SDCARD/etc/systemd/system/haveged.service.d
		cat <<-EOF > $CACHEDIR/$SDCARD/etc/systemd/system/haveged.service.d/10-no-new-privileges.conf
		[Service]
		NoNewPrivileges=false
		EOF

		# disable not working on unneeded services
		# ureadahead needs kernel tracing options that AFAIK are present only in mainline
		chroot $CACHEDIR/$SDCARD /bin/bash -c "systemctl --no-reload mask ondemand.service ureadahead.service setserial.service etc-setserial.service >/dev/null 2>&1"

		# properly disable powersaving wireless mode for NetworkManager
		mkdir -p $CACHEDIR/$SDCARD/etc/NetworkManager/conf.d/
		cat <<-EOF > $CACHEDIR/$SDCARD/etc/NetworkManager/conf.d/zz-override-wifi-powersave-off.conf
		[connection]
		wifi.powersave = 2
		EOF
		;;

	stretch)
	;;
	esac
}

post_debootstrap_tweaks()
{
	# remove service start blockers and QEMU binary
	rm -f $CACHEDIR/$SDCARD/sbin/initctl $CACHEDIR/$SDCARD/sbin/start-stop-daemon
	chroot $CACHEDIR/$SDCARD /bin/bash -c "dpkg-divert --quiet --local --rename --remove /sbin/initctl"
	chroot $CACHEDIR/$SDCARD /bin/bash -c "dpkg-divert --quiet --local --rename --remove /sbin/start-stop-daemon"
	rm -f $CACHEDIR/$SDCARD/usr/sbin/policy-rc.d $CACHEDIR/$SDCARD/usr/bin/$QEMU_BINARY

	# reenable resolvconf managed resolv.conf
	ln -sf /run/resolvconf/resolv.conf $CACHEDIR/$SDCARD/etc/resolv.conf
}
