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
# Create board support packages
#
# Functions:
# create_board_package

create_board_package()
{
	display_alert "Creating board support package" "$BOARD $BRANCH" "info"

	local destination=$DEST/debs/$RELEASE/${CHOSEN_ROOTFS}_${REVISION}_${ARCH}
	rm -rf $destination
	mkdir -p $destination/DEBIAN

	# Replaces: base-files is needed to replace /etc/update-motd.d/ files on Xenial
	# Replaces: unattended-upgrades may be needed to replace /etc/apt/apt.conf.d/50unattended-upgrades
	# (distributions provide good defaults, so this is not needed currently)
	# Depends: linux-base is needed for "linux-version" command in initrd cleanup script
	cat <<-EOF > $destination/DEBIAN/control
	Package: linux-${RELEASE}-root-${DEB_BRANCH}${BOARD}
	Version: $REVISION
	Architecture: $ARCH
	Maintainer: $MAINTAINER <$MAINTAINERMAIL>
	Installed-Size: 1
	Section: kernel
	Priority: optional
	Depends: bash, linux-base, u-boot-tools, initramfs-tools
	Provides: armbian-bsp
	Conflicts: armbian-bsp
	Replaces: base-files, mpv
	Recommends: bsdutils, parted, python3-apt, util-linux, toilet, wireless-tools
	Description: Armbian tweaks for $RELEASE on $BOARD ($BRANCH branch)
	EOF

	# set up pre install script
	cat <<-EOF > $destination/DEBIAN/preinst
	#!/bin/sh
	[ "\$1" = "upgrade" ] && touch /var/run/.reboot_required
	[ -d "/boot/bin.old" ] && rm -rf /boot/bin.old
	[ -d "/boot/bin" ] && mv -f /boot/bin /boot/bin.old
	if [ -L "/etc/network/interfaces" ]; then
		cp /etc/network/interfaces /etc/network/interfaces.tmp
		rm /etc/network/interfaces
		mv /etc/network/interfaces.tmp /etc/network/interfaces
	fi
	# make a backup since we are unconditionally overwriting this on update
	cp /etc/default/cpufrequtils /etc/default/cpufrequtils.dpkg-old
	dpkg-divert --package linux-${RELEASE}-root-${DEB_BRANCH}${BOARD} --add --rename \
		--divert /etc/mpv/mpv-dist.conf /etc/mpv/mpv.conf
	exit 0
	EOF

	chmod 755 $destination/DEBIAN/preinst

	# postrm script
	cat <<-EOF > $destination/DEBIAN/postrm
	#!/bin/sh
	[ remove = "\$1" ] || [ abort-install = "\$1" ] && dpkg-divert --package linux-${RELEASE}-root-${DEB_BRANCH}${BOARD} --remove --rename \
		--divert /etc/mpv/mpv-dist.conf /etc/mpv/mpv.conf
	systemctl disable log2ram.service xdgcache2ram.service armhwinfo.service >/dev/null 2>&1
	exit 0
	EOF

	chmod 755 $destination/DEBIAN/postrm

	# set up post install script
	cat <<-EOF > $destination/DEBIAN/postinst
	#!/bin/sh
	[ ! -f "/etc/network/interfaces" ] && cp /etc/network/interfaces.default /etc/network/interfaces
	ln -sf /var/run/motd /etc/motd
	rm -f /etc/update-motd.d/00-header /etc/update-motd.d/10-help-text
	if [ -f "/boot/bin/$BOARD.bin" ] && [ ! -f "/boot/script.bin" ]; then ln -sf bin/$BOARD.bin /boot/script.bin >/dev/null 2>&1 || cp /boot/bin/$BOARD.bin /boot/script.bin; fi
	rm -f /usr/local/bin/h3disp /usr/local/bin/h3consumption
	[ ! -f /etc/default/armbian-motd ] && cp /usr/lib/armbian/armbian-motd.default /etc/default/armbian-motd
	if [ ! -f "/etc/default/log2ram" ]; then
		cp /etc/default/log2ram.dpkg-dist /etc/default/log2ram
	fi
	if [ -f "/etc/systemd/system/log2ram.service" ]; then
		mv /etc/systemd/system/log2ram.service /etc/systemd/system/log2ram-service.dpkg-old
	fi
	if [ ! -f "/etc/default/xdgcache2ram" ]; then
		cp /etc/default/xdgcache2ram.dpkg-dist /etc/default/xdgcache2ram
	fi
	if [ -f "/etc/systemd/system/xdgcache2ram.service" ]; then
		mv /etc/systemd/system/xdgcache2ram.service /etc/systemd/system/xdgcache2ram-service.dpkg-old
	fi
	exit 0
	EOF

	chmod 755 $destination/DEBIAN/postinst

	# won't recreate files if they were removed by user
	# TODO: Add proper handling for updated conffiles
	#cat <<-EOF > $destination/DEBIAN/conffiles
	#EOF

	# trigger uInitrd creation after installation, to apply
	# /etc/initramfs/post-update.d/99-uboot
	cat <<-EOF > $destination/DEBIAN/triggers
	activate update-initramfs
	EOF

	# create directory structure
	mkdir -p $destination/etc/{init.d,default,update-motd.d,profile.d,network,cron.d,cron.daily}
	mkdir -p $destination/usr/{bin,sbin} $destination/usr/lib/armbian/ $destination/usr/share/armbian/ $destination/usr/share/log2ram/
	mkdir -p $destination/etc/initramfs/post-update.d/
	mkdir -p $destination/etc/kernel/preinst.d/
	mkdir -p $destination/etc/apt/apt.conf.d/ $destination/etc/apt/preferences.d/
	mkdir -p $destination/etc/X11/xorg.conf.d/
	mkdir -p $destination/lib/systemd/system/

	install -m 755 $SRC/lib/scripts/armhwinfo $destination/etc/init.d/

	# configure MIN / MAX speed for cpufrequtils
	cat <<-EOF > $destination/etc/default/cpufrequtils
	ENABLE=true
	MIN_SPEED=$CPUMIN
	MAX_SPEED=$CPUMAX
	GOVERNOR=$GOVERNOR
	EOF

	# armhwinfo, firstrun, armbianmonitor, etc. config file
	cat <<-EOF > $destination/etc/armbian-release
	# PLEASE DO NOT EDIT THIS FILE
	BOARD=$BOARD
	BOARD_NAME="$BOARD_NAME"
	VERSION=$REVISION
	LINUXFAMILY=$LINUXFAMILY
	BRANCH=$BRANCH
	ARCH=$ARCHITECTURE
	IMAGE_TYPE=$IMAGE_TYPE
	EOF

	# add USB OTG port mode switcher
	install -m 755 $SRC/lib/scripts/sunxi-musb $destination/usr/bin

	# armbianmonitor (currently only to toggle boot verbosity and log upload)
	install -m 755 $SRC/lib/scripts/armbianmonitor/armbianmonitor $destination/usr/bin

	# updating uInitrd image in update-initramfs trigger
	cat <<-EOF > $destination/etc/initramfs/post-update.d/99-uboot
	#!/bin/sh
	echo "update-initramfs: Converting to u-boot format" >&2
	tempname="/boot/uInitrd-\$1"
	mkimage -A $INITRD_ARCH -O linux -T ramdisk -C gzip -n uInitrd -d \$2 \$tempname > /dev/null
	ln -sf \$(basename \$tempname) /boot/uInitrd > /dev/null 2>&1 || mv \$tempname /boot/uInitrd
	exit 0
	EOF
	chmod +x $destination/etc/initramfs/post-update.d/99-uboot

	# removing old initrd.img on upgrade
	cat <<-EOF > $destination/etc/kernel/preinst.d/initramfs-cleanup
	#!/bin/sh
	version="\$1"
	[ -x /usr/sbin/update-initramfs ] || exit 0
	# passing the kernel version is required
	if [ -z "\${version}" ]; then
		echo >&2 "W: initramfs-tools: \${DPKG_MAINTSCRIPT_PACKAGE:-kernel package} did not pass a version number"
		exit 0
	fi
	# avoid running multiple times
	if [ -n "\$DEB_MAINT_PARAMS" ]; then
		eval set -- "\$DEB_MAINT_PARAMS"
		if [ -z "\$1" ] || [ "\$1" != "upgrade" ]; then
			exit 0
		fi
	fi
	STATEDIR=/var/lib/initramfs-tools
	version_list="\$(ls -1 "\${STATEDIR}" | linux-version sort --reverse)"
	for v in \$version_list; do
		if ! linux-version compare \$v eq \$version; then
			# try to delete delete old initrd images via update-initramfs
			INITRAMFS_TOOLS_KERNEL_HOOK=y update-initramfs -d -k \$v 2>/dev/null
			# delete unused state files
			find \$STATEDIR -type f ! -name "\$version" -printf "Removing obsolete file %f\n" -delete
			# delete unused initrd images
			find /boot -name "initrd.img*" -o -name "uInitrd-*" ! -name "*\$version" -printf "Removing obsolete file %f\n" -delete
		fi
	done
	EOF
	chmod +x $destination/etc/kernel/preinst.d/initramfs-cleanup

	# network interfaces configuration
	cp $SRC/lib/config/network/interfaces.* $destination/etc/network/
	[[ $RELEASE = xenial ]] && sed -i 's/#no-auto-down/no-auto-down/g' $destination/etc/network/interfaces.default

	# apt configuration
	cat <<-EOF > $destination/etc/apt/apt.conf.d/71-no-recommends
	APT::Install-Recommends "0";
	APT::Install-Suggests "0";
	EOF

	# xorg configuration
	cat <<-EOF > $destination/etc/X11/xorg.conf.d/01-armbian-defaults.conf
	Section "Monitor"
		Identifier		"Monitor0"
		Option			"DPMS" "false"
	EndSection
	Section "ServerFlags"
		Option			"BlankTime" "0"
		Option			"StandbyTime" "0"
		Option			"SuspendTime" "0"
		Option			"OffTime" "0"
	EndSection
	EOF

	# configure the system for unattended upgrades
	cp $SRC/lib/scripts/02periodic $destination/etc/apt/apt.conf.d/02periodic

	# pin priority for armbian repo
	# reference: man apt_preferences
	# this allows providing own versions of hostapd, libdri2 and sunxi-tools
	cat <<-EOF > $destination/etc/apt/preferences.d/50-armbian.pref
	Package: *
	Pin: origin "apt.armbian.com"
	Pin-Priority: 500
	EOF

	# script to install to SATA
	cp -R $SRC/lib/scripts/nand-sata-install/usr $destination/
	chmod +x $destination/usr/lib/nand-sata-install/nand-sata-install.sh
	ln -s ../lib/nand-sata-install/nand-sata-install.sh $destination/usr/sbin/nand-sata-install

	# configuration script
	# TODO: better git update logic
	if [[ -d $SRC/sources/Debian-micro-home-server ]]; then
		git --work-tree=$SRC/sources/Debian-micro-home-server --git-dir=$SRC/sources/Debian-micro-home-server/.git pull
	else
		git clone https://github.com/igorpecovnik/Debian-micro-home-server $SRC/sources/Debian-micro-home-server
	fi

	install -m 755 $SRC/sources/Debian-micro-home-server/scripts/tv_grab_file $destination/usr/bin/tv_grab_file
	install -m 755 $SRC/sources/Debian-micro-home-server/debian-config $destination/usr/bin/armbian-config
	install -m 755 $SRC/sources/Debian-micro-home-server/softy $destination/usr/bin/softy

	# install custom motd with reboot and upgrade checking
	install -m 755 $SRC/lib/scripts/update-motd.d/* $destination/etc/update-motd.d/
	cp $SRC/lib/scripts/check_first_login_reboot.sh $destination/etc/profile.d
	cp $SRC/lib/scripts/check_first_login.sh $destination/etc/profile.d

	install -m 755 $SRC/lib/scripts/apt-updates $destination/usr/lib/armbian/apt-updates

	cat <<-EOF > $destination/usr/lib/armbian/armbian-motd.default
	# add space-separated list of MOTD script names (without number) to exclude them from MOTD
	# Example:
	# MOTD_DISABLE="header tips updates"
	MOTD_DISABLE=""
	EOF

	cat <<-EOF > $destination/etc/cron.d/armbian-updates
	@reboot root /usr/lib/armbian/apt-updates
	@daily root /usr/lib/armbian/apt-updates
	EOF

	# setting window title for remote sessions
	install -m 755 $SRC/lib/scripts/ssh-title.sh $destination/etc/profile.d/ssh-title.sh

	# install copy of boot script & environment file
	local bootscript_src=${BOOTSCRIPT%%:*}
	local bootscript_dst=${BOOTSCRIPT##*:}
	cp $SRC/lib/config/bootscripts/$bootscript_src $destination/usr/share/armbian/$bootscript_dst
	[[ -n $BOOTENV_FILE && -f $SRC/lib/config/bootenv/$BOOTENV_FILE ]] && \
		cp $SRC/lib/config/bootenv/$BOOTENV_FILE $destination/usr/share/armbian/armbianEnv.txt

	# h3disp for sun8i/3.4.x
	if [[ $LINUXFAMILY == sun8i && $BRANCH == default ]]; then
		install -m 755 $SRC/lib/scripts/h3disp $destination/usr/bin
		install -m 755 $SRC/lib/scripts/h3consumption $destination/usr/bin
	fi

	# add configuration for setting uboot environment from userspace with: fw_setenv fw_printenv
	if [[ -n $UBOOT_FW_ENV ]]; then
		UBOOT_FW_ENV=($(tr ',' ' ' <<< "$UBOOT_FW_ENV"))
		echo "# Device to access      offset           env size" > $destination/etc/fw_env.config
		echo "/dev/mmcblk0	${UBOOT_FW_ENV[0]}	${UBOOT_FW_ENV[1]}" >> $destination/etc/fw_env.config
	fi

	# log2ram - systemd compatible ramlog alternative
	cp $SRC/lib/scripts/log2ram/LICENSE.log2ram $destination/usr/share/log2ram/LICENSE
	cp $SRC/lib/scripts/log2ram/log2ram.service $destination/lib/systemd/system/log2ram.service
	install -m 755 $SRC/lib/scripts/log2ram/log2ram $destination/usr/sbin/log2ram
	install -m 755 $SRC/lib/scripts/log2ram/log2ram.hourly $destination/etc/cron.daily/log2ram
	cp $SRC/lib/scripts/log2ram/log2ram.default $destination/etc/default/log2ram.dpkg-dist

	# xdgcache2ram - persistent xdgcache based on log2ram
	cp $SRC/lib/scripts/log2ram/xdgcache2ram.service $destination/lib/systemd/system/xdgcache2ram.service
	ln -s /usr/sbin/log2ram $destination/usr/sbin/xdgcache2ram
	cp $SRC/lib/scripts/log2ram/xdgcache2ram.default $destination/etc/default/xdgcache2ram.dpkg-dist

	if [[ $LINUXFAMILY == sun*i ]]; then
		install -m 755 $SRC/lib/scripts/armbian-add-overlay $destination/usr/sbin
		if [[ $BRANCH == default ]]; then
			# add soc temperature app
			local codename=$(lsb_release -sc)
			if [[ -z $codename || "sid" == *"$codename"* ]]; then
				arm-linux-gnueabihf-gcc-5 $SRC/lib/scripts/sunxi-temp/sunxi_tp_temp.c -o $destination/usr/bin/sunxi_tp_temp
			else
				arm-linux-gnueabihf-gcc $SRC/lib/scripts/sunxi-temp/sunxi_tp_temp.c -o $destination/usr/bin/sunxi_tp_temp
			fi
		fi

		# convert and add fex files
		mkdir -p $destination/boot/bin
		for i in $(ls -w1 $SRC/lib/config/fex/*.fex | xargs -n1 basename); do
			fex2bin $SRC/lib/config/fex/${i%*.fex}.fex $destination/boot/bin/${i%*.fex}.bin
		done
	fi

	if [[ ( $LINUXFAMILY == sun*i || $LINUXFAMILY == pine64 ) && $BRANCH == default ]]; then
		# add mpv config for vdpau_sunxi
		mkdir -p $destination/etc/mpv/
		cp $SRC/lib/config/mpv_sunxi.conf $destination/etc/mpv/mpv.conf
		echo "export VDPAU_OSD=1" > $destination/etc/profile.d/90-vdpau.sh
		chmod 755 $destination/etc/profile.d/90-vdpau.sh
	fi
	if [[ ( $LINUXFAMILY == sun50iw2 || $LINUXFAMILY == sun8i || $LINUXFAMILY == pine64 ) && $BRANCH == dev ]]; then
		# add mpv config for x11 output - slow, but it works compared to no config at all
		mkdir -p $destination/etc/mpv/
		cat <<-EOF > $destination/etc/mpv/mpv.conf
		# HW acceleration is not supported on this platform yet
		vo=x11
		EOF
	fi

	# add some summary to the image
	fingerprint_image "$destination/etc/armbian.txt"

	# create board DEB file
	display_alert "Building package" "$CHOSEN_ROOTFS" "info"
	cd $DEST/debs/$RELEASE/
	dpkg -b ${CHOSEN_ROOTFS}_${REVISION}_${ARCH} >/dev/null

	# cleanup
	rm -rf ${CHOSEN_ROOTFS}_${REVISION}_${ARCH}
}
