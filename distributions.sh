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
# install_distribution_specific

install_distribution_specific (){
#---------------------------------------------------------------------------------------------------------------------------------
# Install board common applications
#---------------------------------------------------------------------------------------------------------------------------------
display_alert "Applying distribution specific tweaks for" "$RELEASE" "info"

# Common

# set up apt
cat <<END > $CACHEDIR/sdcard/etc/apt/apt.conf.d/71-no-recommends
APT::Install-Recommends "0";
APT::Install-Suggests "0";
END

# configure the system for unattended upgrades
cp $SRC/lib/scripts/50unattended-upgrades $CACHEDIR/sdcard/etc/apt/apt.conf.d/50unattended-upgrades
cp $SRC/lib/scripts/02periodic $CACHEDIR/sdcard/etc/apt/apt.conf.d/02periodic

# setting window title for remote sessions
mkdir -p $CACHEDIR/sdcard/etc/profile.d
install -m 755 $SRC/lib/scripts/ssh-title.sh $CACHEDIR/sdcard/etc/profile.d/ssh-title.sh

case $RELEASE in

# Debian Wheezy
wheezy)
		# add serial console
		echo T0:2345:respawn:/sbin/getty -L $SERIALCON 115200 vt100 >> $CACHEDIR/sdcard/etc/inittab

		# don't clear screen on boot console
		sed -e 's/getty 38400 tty1/getty --noclear 38400 tty1/g' -i $CACHEDIR/sdcard/etc/inittab

		# disable some getties
		sed -e 's/5:23:respawn/#5:23:respawn/g' -i $CACHEDIR/sdcard/etc/inittab
		sed -e 's/6:23:respawn/#6:23:respawn/g' -i $CACHEDIR/sdcard/etc/inittab

		# auto upgrading
		sed -e "s/ORIGIN/Debian/g" -i $CACHEDIR/sdcard/etc/apt/apt.conf.d/50unattended-upgrades
		sed -e "s/n=CODENAME/a=old-stable/g" -i $CACHEDIR/sdcard/etc/apt/apt.conf.d/50unattended-upgrades

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

# Debian Jessie
jessie)
		# enable root login for latest ssh on jessie
		sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' $CACHEDIR/sdcard/etc/ssh/sshd_config

		# auto upgrading
		sed -e "s/ORIGIN/Debian/g" -i $CACHEDIR/sdcard/etc/apt/apt.conf.d/50unattended-upgrades
		sed -e "s/CODENAME/$RELEASE/g" -i $CACHEDIR/sdcard/etc/apt/apt.conf.d/50unattended-upgrades

		# mount 256Mb tmpfs to /tmp
		echo "tmpfs   /tmp         tmpfs   nodev,nosuid,size=256M          0  0" >> $CACHEDIR/sdcard/etc/fstab

		# fix selinux error
		mkdir $CACHEDIR/sdcard/selinux

		# add serial console
		cp $SRC/lib/config/ttyS0.conf $CACHEDIR/sdcard/etc/init/$SERIALCON.conf
		sed -e "s/ttyS0/$SERIALCON/g" -i $CACHEDIR/sdcard/etc/init/$SERIALCON.conf
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

# Ubuntu Trusty
trusty)
		# add serial console
		cp $SRC/lib/config/ttyS0.conf $CACHEDIR/sdcard/etc/init/$SERIALCON.conf
		sed -e "s/ttyS0/$SERIALCON/g" -i $CACHEDIR/sdcard/etc/init/$SERIALCON.conf

		# don't clear screen tty1
		sed -e s,"exec /sbin/getty","exec /sbin/getty --noclear",g 	-i $CACHEDIR/sdcard/etc/init/tty1.conf

		# disable some getties
		rm -f $CACHEDIR/sdcard/etc/init/tty5.conf
		rm -f $CACHEDIR/sdcard/etc/init/tty6.conf

		# enable root login for latest ssh on trusty
		sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' $CACHEDIR/sdcard/etc/ssh/sshd_config

		# fix selinux error
		mkdir $CACHEDIR/sdcard/selinux

		# remove legal info from Ubuntu
		[[ -f $CACHEDIR/sdcard/etc/legal ]] && rm $CACHEDIR/sdcard/etc/legal
		
		# that my custom motd works well
		if [[ -d $CACHEDIR/sdcard/etc/update-motd.d ]]; then
			mv $CACHEDIR/sdcard/etc/update-motd.d $CACHEDIR/sdcard/etc/update-motd.d-backup
		fi

		# auto upgrading
		sed -e "s/ORIGIN/Ubuntu/g" -i $CACHEDIR/sdcard/etc/apt/apt.conf.d/50unattended-upgrades
		sed -e "s/CODENAME/$RELEASE/g" -i $CACHEDIR/sdcard/etc/apt/apt.conf.d/50unattended-upgrades

		# remove what's anyway not working
		#chroot $CACHEDIR/sdcard /bin/bash -c "apt-get remove --auto-remove ureadahead"
		rm $CACHEDIR/sdcard/etc/init/ureadahead*
		rm $CACHEDIR/sdcard/etc/init/plymouth*
		;;

xenial)
		# enable root login for latest ssh on jessie
		sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' $CACHEDIR/sdcard/etc/ssh/sshd_config

		# auto upgrading (disabled while testing)
		sed -e "s/ORIGIN/Ubuntu/g" -i $CACHEDIR/sdcard/etc/apt/apt.conf.d/50unattended-upgrades
		sed -e "s/CODENAME/$RELEASE/g" -i $CACHEDIR/sdcard/etc/apt/apt.conf.d/50unattended-upgrades

		# fix selinux error
		mkdir $CACHEDIR/sdcard/selinux
		
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

		# disable stopping network interfaces
		# fixes shutdown with root on NFS
		mkdir -p $CACHEDIR/sdcard/etc/systemd/system/networking.service.d/
		printf "[Service]\nExecStop=\n" > $CACHEDIR/sdcard/etc/systemd/system/networking.service.d/10-nostop.conf
		;;
	*)
	exit_with_error "Unknown OS release selected"
	;;
esac

# copy hostapd configurations
install -m 755 $SRC/lib/config/hostapd/hostapd.conf $CACHEDIR/sdcard/etc/hostapd.conf
install -m 755 $SRC/lib/config/hostapd/hostapd.realtek.conf $CACHEDIR/sdcard/etc/hostapd.conf-rt

# console fix due to Debian bug
sed -e 's/CHARMAP=".*"/CHARMAP="'$CONSOLE_CHAR'"/g' -i $CACHEDIR/sdcard/etc/default/console-setup

# root-fs modifications
rm 	-f $CACHEDIR/sdcard/etc/motd
touch $CACHEDIR/sdcard/etc/motd

# change time zone data
echo $TZDATA > $CACHEDIR/sdcard/etc/timezone
chroot $CACHEDIR/sdcard /bin/bash -c "dpkg-reconfigure -f noninteractive tzdata >/dev/null 2>&1"

# set root password
chroot $CACHEDIR/sdcard /bin/bash -c "(echo $ROOTPWD;echo $ROOTPWD;) | passwd root >/dev/null 2>&1"

# create proper fstab
if [[ $BOOTSIZE -eq 0 ]]; then
	local device="/dev/mmcblk0p1	/           ext4    defaults,noatime,nodiratime,data=writeback,commit=600,errors=remount-ro"
else
	local device="/dev/mmcblk0p2	/           ext4    defaults,noatime,nodiratime,data=writeback,commit=600,errors=remount-ro"
fi
echo "$device        0       0" >> $CACHEDIR/sdcard/etc/fstab

# flash media tunning
if [[ -f $CACHEDIR/sdcard/etc/default/tmpfs ]]; then
	sed -e 's/#RAMTMP=no/RAMTMP=yes/g' -i $CACHEDIR/sdcard/etc/default/tmpfs
	sed -e 's/#RUN_SIZE=10%/RUN_SIZE=128M/g' -i $CACHEDIR/sdcard/etc/default/tmpfs
	sed -e 's/#LOCK_SIZE=/LOCK_SIZE=/g' -i $CACHEDIR/sdcard/etc/default/tmpfs
	sed -e 's/#SHM_SIZE=/SHM_SIZE=128M/g' -i $CACHEDIR/sdcard/etc/default/tmpfs
	sed -e 's/#TMP_SIZE=/TMP_SIZE=1G/g' -i $CACHEDIR/sdcard/etc/default/tmpfs
fi

# add custom bashrc loading
cat <<END >> $CACHEDIR/sdcard/etc/bash.bashrc
if [[ -f /etc/bash.bashrc.custom ]]; then
    . /etc/bash.bashrc.custom
fi
END

# display welcome message at first root login
touch $CACHEDIR/sdcard/root/.not_logged_in_yet

# force change root password at first login
chroot $CACHEDIR/sdcard /bin/bash -c "chage -d 0 root"

# remove hostapd because it's replaced with ours
chroot $CACHEDIR/sdcard /bin/bash -c "apt-get -y -qq remove hostapd >/dev/null 2>&1"

# install sunxi-tools
cp $SRC/lib/bin/sunxi-tools_1.3-1_armhf.deb $CACHEDIR/sdcard/tmp/
# libusb dependency should already be satisfied by usbutils
chroot $CACHEDIR/sdcard /bin/bash -c "dpkg -i /tmp/sunxi-tools_1.3-1_armhf.deb >/dev/null 2>&1"
}
