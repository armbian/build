# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# Functions:
# install_common
# install_distribution_specific
# post_debootstrap_tweaks

install_common()
{
	display_alert "Applying common tweaks" "" "info"

	# define ARCH within global environment variables
	[[ -f $SDCARD/etc/environment ]] && echo "ARCH=${ARCH//hf}" >> $SDCARD/etc/environment

	# add dummy fstab entry to make mkinitramfs happy
	echo "/dev/mmcblk0p1 / $ROOTFS_TYPE defaults 0 1" >> $SDCARD/etc/fstab
	# required for initramfs-tools-core on Stretch since it ignores the / fstab entry
	echo "/dev/mmcblk0p2 /usr $ROOTFS_TYPE defaults 0 2" >> $SDCARD/etc/fstab

	# create modules file
	if [[ $BRANCH == dev && -n $MODULES_DEV ]]; then
		tr ' ' '\n' <<< "$MODULES_DEV" > $SDCARD/etc/modules
	elif [[ $BRANCH == next || $BRANCH == dev ]]; then
		tr ' ' '\n' <<< "$MODULES_NEXT" > $SDCARD/etc/modules
	else
		tr ' ' '\n' <<< "$MODULES" > $SDCARD/etc/modules
	fi

	# create blacklist files
	if [[ $BRANCH == dev && -n $MODULES_BLACKLIST_DEV ]]; then
		tr ' ' '\n' <<< "$MODULES_BLACKLIST_DEV" | sed -e 's/^/blacklist /' > $SDCARD/etc/modprobe.d/blacklist-${BOARD}.conf
	elif [[ ($BRANCH == next || $BRANCH == dev) && -n $MODULES_BLACKLIST_NEXT ]]; then
		tr ' ' '\n' <<< "$MODULES_BLACKLIST_NEXT" | sed -e 's/^/blacklist /' > $SDCARD/etc/modprobe.d/blacklist-${BOARD}.conf
	elif [[ $BRANCH == default && -n $MODULES_BLACKLIST ]]; then
		tr ' ' '\n' <<< "$MODULES_BLACKLIST" | sed -e 's/^/blacklist /' > $SDCARD/etc/modprobe.d/blacklist-${BOARD}.conf
	fi

	# remove default interfaces file if present
	# before installing board support package
	rm -f $SDCARD/etc/network/interfaces

	mkdir -p $SDCARD/selinux

	# remove Ubuntu's legal text
	[[ -f $SDCARD/etc/legal ]] && rm $SDCARD/etc/legal

	# Prevent loading paralel printer port drivers which we don't need here.Suppress boot error if kernel modules are absent
	if [[ -f $SDCARD/etc/modules-load.d/cups-filters.conf ]]; then
		sed "s/^lp/#lp/" -i $SDCARD/etc/modules-load.d/cups-filters.conf
		sed "s/^ppdev/#ppdev/" -i $SDCARD/etc/modules-load.d/cups-filters.conf
		sed "s/^parport_pc/#parport_pc/" -i $SDCARD/etc/modules-load.d/cups-filters.conf
	fi

	# console fix due to Debian bug
	sed -e 's/CHARMAP=".*"/CHARMAP="'$CONSOLE_CHAR'"/g' -i $SDCARD/etc/default/console-setup

	# change time zone data
	echo $TZDATA > $SDCARD/etc/timezone
	chroot $SDCARD /bin/bash -c "dpkg-reconfigure -f noninteractive tzdata >/dev/null 2>&1"

	# set root password
	chroot $SDCARD /bin/bash -c "(echo $ROOTPWD;echo $ROOTPWD;) | passwd root >/dev/null 2>&1"
	# force change root password at first login
	chroot $SDCARD /bin/bash -c "chage -d 0 root"

	# display welcome message at first root login
	touch $SDCARD/root/.not_logged_in_yet

	# NOTE: this needs to be executed before family_tweaks
	local bootscript_src=${BOOTSCRIPT%%:*}
	local bootscript_dst=${BOOTSCRIPT##*:}
	cp $SRC/config/bootscripts/$bootscript_src $SDCARD/boot/$bootscript_dst

	[[ -n $BOOTENV_FILE && -f $SRC/config/bootenv/$BOOTENV_FILE ]] && \
		cp $SRC/config/bootenv/$BOOTENV_FILE $SDCARD/boot/armbianEnv.txt

	# TODO: modify $bootscript_dst or armbianEnv.txt to make NFS boot universal
	# instead of copying sunxi-specific template
	if [[ $ROOTFS_TYPE == nfs ]]; then
		display_alert "Copying NFS boot script template"
		if [[ -f $SRC/userpatches/nfs-boot.cmd ]]; then
			cp $SRC/userpatches/nfs-boot.cmd $SDCARD/boot/boot.cmd
		else
			cp $SRC/config/templates/nfs-boot.cmd.template $SDCARD/boot/boot.cmd
		fi
	fi

	[[ -n $OVERLAY_PREFIX && -f $SDCARD/boot/armbianEnv.txt ]] && \
		echo "overlay_prefix=$OVERLAY_PREFIX" >> $SDCARD/boot/armbianEnv.txt

	[[ -n $DEFAULT_OVERLAYS && -f $SDCARD/boot/armbianEnv.txt ]] && \
		echo "overlays=${DEFAULT_OVERLAYS//,/ }" >> $SDCARD/boot/armbianEnv.txt

	# initial date for fake-hwclock
	date -u '+%Y-%m-%d %H:%M:%S' > $SDCARD/etc/fake-hwclock.data

	echo $HOST > $SDCARD/etc/hostname

	# set hostname in hosts file
	cat <<-EOF > $SDCARD/etc/hosts
	127.0.0.1   localhost $HOST
	::1         localhost $HOST ip6-localhost ip6-loopback
	fe00::0     ip6-localnet
	ff00::0     ip6-mcastprefix
	ff02::1     ip6-allnodes
	ff02::2     ip6-allrouters
	EOF

	# install kernel and u-boot packages
	install_deb_chroot "$DEST/debs/${CHOSEN_KERNEL}_${REVISION}_${ARCH}.deb"
	install_deb_chroot "$DEST/debs/${CHOSEN_UBOOT}_${REVISION}_${ARCH}.deb"

	if [[ $BUILD_DESKTOP == yes ]]; then
		install_deb_chroot "$DEST/debs/$RELEASE/armbian-${RELEASE}-desktop_${REVISION}_all.deb"
		# install display manager
		desktop_postinstall
	fi

	if [[ $INSTALL_HEADERS == yes ]]; then
		install_deb_chroot "$DEST/debs/${CHOSEN_KERNEL/image/headers}_${REVISION}_${ARCH}.deb"
	fi

	if [[ -f $DEST/debs/armbian-firmware_${REVISION}_${ARCH}.deb ]]; then
		install_deb_chroot "$DEST/debs/armbian-firmware_${REVISION}_${ARCH}.deb"
	fi

	if [[ -f $DEST/debs/${CHOSEN_KERNEL/image/dtb}_${REVISION}_${ARCH}.deb ]]; then
		install_deb_chroot "$DEST/debs/${CHOSEN_KERNEL/image/dtb}_${REVISION}_${ARCH}.deb"
	fi

	if [[ -f $DEST/debs/${CHOSEN_KSRC}_${REVISION}_all.deb && $INSTALL_KSRC == yes ]]; then
		install_deb_chroot "$DEST/debs/${CHOSEN_KSRC}_${REVISION}_all.deb"
	fi

	# install board support package
	install_deb_chroot "$DEST/debs/$RELEASE/${CHOSEN_ROOTFS}_${REVISION}_${ARCH}.deb"

	# freeze armbian packages
	if [[ $BSPFREEZE == yes ]]; then
		display_alert "Freezing Armbian packages" "$BOARD" "info"
		chroot $SDCARD /bin/bash -c "apt-mark hold ${CHOSEN_KERNEL} ${CHOSEN_KERNEL/image/headers} \
			linux-u-boot-${BOARD}-${BRANCH} ${CHOSEN_KERNEL/image/dtb}" >> $DEST/debug/install.log 2>&1
	fi

	# copy boot splash images
	cp $SRC/packages/blobs/splash/armbian-u-boot.bmp $SDCARD/boot/boot.bmp
	cp $SRC/packages/blobs/splash/armbian-desktop.png $SDCARD/boot/boot-desktop.png

	# execute $LINUXFAMILY-specific tweaks
	[[ $(type -t family_tweaks) == function ]] && family_tweaks

	# enable additional services
	chroot $SDCARD /bin/bash -c "systemctl --no-reload enable armbian-firstrun.service armbian-firstrun-config.service armbian-zram-config.service armbian-hardware-optimize.service armbian-ramlog.service armbian-resize-filesystem.service armbian-hardware-monitor.service >/dev/null 2>&1"

	# copy "first run automated config, optional user configured"
 	cp $SRC/packages/bsp/armbian_first_run.txt.template $SDCARD/boot/armbian_first_run.txt.template

	# switch to beta repository at this stage if building nightly images
	[[ $IMAGE_TYPE == nightly ]] && echo "deb http://beta.armbian.com $RELEASE main ${RELEASE}-utils ${RELEASE}-desktop" > $SDCARD/etc/apt/sources.list.d/armbian.list

	# Cosmetic fix [FAILED] Failed to start Set console font and keymap at first boot
	[[ -f $SDCARD/etc/console-setup/cached_setup_font.sh ]] && sed -i "s/^printf '.*/printf '\\\033\%\%G'/g" $SDCARD/etc/console-setup/cached_setup_font.sh
	[[ -f $SDCARD/etc/console-setup/cached_setup_terminal.sh ]] && sed -i "s/^printf '.*/printf '\\\033\%\%G'/g" $SDCARD/etc/console-setup/cached_setup_terminal.sh
	[[ -f $SDCARD/etc/console-setup/cached_setup_keyboard.sh ]] && sed -i "s/-u/-x'/g" $SDCARD/etc/console-setup/cached_setup_keyboard.sh

	# disable low-level kernel messages for non betas
	# TODO: enable only for desktop builds?
	if [[ -z $BETA ]]; then
		sed -i "s/^#kernel.printk*/kernel.printk/" $SDCARD/etc/sysctl.conf
	fi

	# disable repeated messages due to xconsole not being installed.
	[[ -f $SDCARD/etc/rsyslog.d/50-default.conf ]] && sed '/daemon\.\*\;mail.*/,/xconsole/ s/.*/#&/' -i $SDCARD/etc/rsyslog.d/50-default.conf
	# disable deprecated parameter
	sed '/.*$KLogPermitNonKernelFacility.*/,// s/.*/#&/' -i $SDCARD/etc/rsyslog.conf

	# enable getty on serial console
	chroot $SDCARD /bin/bash -c "systemctl --no-reload enable serial-getty@$SERIALCON.service >/dev/null 2>&1"

	[[ $LINUXFAMILY == sun*i ]] && mkdir -p $SDCARD/boot/overlay-user

	# to prevent creating swap file on NFS (needs specific kernel options)
	# and f2fs/btrfs (not recommended or needs specific kernel options)
	[[ $ROOTFS_TYPE != ext4 ]] && touch $SDCARD/var/swap

	# install initial asound.state if defined
	mkdir -p $SDCARD/var/lib/alsa/
	[[ -n $ASOUND_STATE ]] && cp $SRC/packages/blobs/asound.state/$ASOUND_STATE $SDCARD/var/lib/alsa/asound.state

	# save initial armbian-release state
	cp $SDCARD/etc/armbian-release $SDCARD/etc/armbian-image-release

	# DNS fix. package resolvconf is not available everywhere
	if [ -d /etc/resolvconf/resolv.conf.d ]; then
		echo 'nameserver 1.1.1.1' > $SDCARD/etc/resolvconf/resolv.conf.d/head
	fi

	# premit root login via SSH for the first boot
	sed -i 's/#\?PermitRootLogin .*/PermitRootLogin yes/' $SDCARD/etc/ssh/sshd_config

	# enable PubkeyAuthentication. Enabled by default everywhere except on Jessie
	sed -i 's/#\?PubkeyAuthentication .*/PubkeyAuthentication yes/' $SDCARD/etc/ssh/sshd_config

	# configure network manager
	sed "s/managed=\(.*\)/managed=true/g" -i $SDCARD/etc/NetworkManager/NetworkManager.conf
	# disable DNS management withing NM for !Stretch
	#[[ $RELEASE != stretch || $RELEASE != jessie || $RELEASE != bionic ]] && sed "s/\[main\]/\[main\]\ndns=none/g" -i $SDCARD/etc/NetworkManager/NetworkManager.conf
	if [[ -n $NM_IGNORE_DEVICES ]]; then
		mkdir -p $SDCARD/etc/NetworkManager/conf.d/
		cat <<-EOF > $SDCARD/etc/NetworkManager/conf.d/10-ignore-interfaces.conf
		[keyfile]
		unmanaged-devices=$NM_IGNORE_DEVICES
		EOF
	fi
}

install_distribution_specific()
{
	display_alert "Applying distribution specific tweaks for" "$RELEASE" "info"
	case $RELEASE in
	jessie)
		if [[ -z $NM_IGNORE_DEVICES ]]; then
			echo "# Network Manager under Jessie doesn't work properly. Workaround" >> $SDCARD/etc/network/interfaces.d/eth0.conf
			echo "auto eth0" >> $SDCARD/etc/network/interfaces.d/eth0.conf
			echo "iface eth0 inet dhcp" >> $SDCARD/etc/network/interfaces.d/eth0.conf
			echo "[keyfile]" >> $SDCARD/etc/NetworkManager/NetworkManager.conf
			echo "unmanaged-devices=interface-name:eth0" >> $SDCARD/etc/NetworkManager/NetworkManager.conf
		fi
		;;

	xenial)
		# remove legal info from Ubuntu
		[[ -f $SDCARD/etc/legal ]] && rm $SDCARD/etc/legal

		# disable not working on unneeded services
		# ureadahead needs kernel tracing options that AFAIK are present only in mainline
		chroot $SDCARD /bin/bash -c "systemctl --no-reload mask ondemand.service ureadahead.service setserial.service etc-setserial.service >/dev/null 2>&1"
		;;

	stretch)
		# remove doubled uname from motd
		[[ -f $SDCARD/etc/update-motd.d/10-uname ]] && rm $SDCARD/etc/update-motd.d/10-uname
		# rc.local is not existing in stretch but we might need it
		cat <<-EOF > $SDCARD/etc/rc.local
		#!/bin/sh -e
		#
		# rc.local
		#
		# This script is executed at the end of each multiuser runlevel.
		# Make sure that the script will "exit 0" on success or any other
		# value on error.
		#
		# In order to enable or disable this script just change the execution
		# bits.
		#
		# By default this script does nothing.

		exit 0
		EOF
		chmod +x $SDCARD/etc/rc.local
		# DNS fix
		sed -i "s/#DNS=.*/DNS=1.1.1.1/g" $SDCARD/etc/systemd/resolved.conf
		;;
	bionic)
		# remove doubled uname from motd
		[[ -f $SDCARD/etc/update-motd.d/10-uname ]] && rm $SDCARD/etc/update-motd.d/10-uname
		# remove motd news from motd.ubuntu.com
		[[ -f $SDCARD/etc/default/motd-news ]] && sed -i "s/^ENABLED=.*/ENABLED=0/" $SDCARD/etc/default/motd-news
		# rc.local is not existing in bionic but we might need it
		cat <<-EOF > $SDCARD/etc/rc.local
		#!/bin/sh -e
		#
		# rc.local
		#
		# This script is executed at the end of each multiuser runlevel.
		# Make sure that the script will "exit 0" on success or any other
		# value on error.
		#
		# In order to enable or disable this script just change the execution
		# bits.
		#
		# By default this script does nothing.

		exit 0
		EOF
		chmod +x $SDCARD/etc/rc.local
		# Basic Netplan config. Let NetworkManager manage all devices on this system
		cat <<-EOF > $SDCARD/etc/netplan/armbian-default.yaml
		network:
		  version: 2
		  renderer: NetworkManager
		EOF
		# DNS fix
		sed -i "s/#DNS=.*/DNS=1.1.1.1/g" $SDCARD/etc/systemd/resolved.conf
		# Journal service adjustements
		sed -i "s/#Storage=.*/Storage=volatile/g" $SDCARD/etc/systemd/journald.conf
		sed -i "s/#Compress=.*/Compress=yes/g" $SDCARD/etc/systemd/journald.conf
		sed -i "s/#RateLimitIntervalSec=.*/RateLimitIntervalSec=30s/g" $SDCARD/etc/systemd/journald.conf
		sed -i "s/#RateLimitBurst=.*/RateLimitBurst=10000/g" $SDCARD/etc/systemd/journald.conf
		;;
	esac
}

post_debootstrap_tweaks()
{
	# remove service start blockers and QEMU binary
	rm -f $SDCARD/sbin/initctl $SDCARD/sbin/start-stop-daemon
	chroot $SDCARD /bin/bash -c "dpkg-divert --quiet --local --rename --remove /sbin/initctl"
	chroot $SDCARD /bin/bash -c "dpkg-divert --quiet --local --rename --remove /sbin/start-stop-daemon"

	chroot $SDCARD /bin/bash -c 'echo "resolvconf resolvconf/linkify-resolvconf boolean true" | debconf-set-selections'
	mkdir -p $SDCARD/var/lib/resolvconf/
	:> $SDCARD/var/lib/resolvconf/linkified

	rm -f $SDCARD/usr/sbin/policy-rc.d $SDCARD/usr/bin/$QEMU_BINARY

	# reenable resolvconf managed resolv.conf
	ln -sf /run/resolvconf/resolv.conf $SDCARD/etc/resolv.conf
}
