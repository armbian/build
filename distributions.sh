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
display_alert "Fixing release custom applications." "$RELEASE" "info"

# Common

# set up apt
cat <<END > $DEST/cache/sdcard/etc/apt/apt.conf.d/71-no-recommends
APT::Install-Recommends "0";
APT::Install-Suggests "0";
END

# configure the system for unattended upgrades
cp $SRC/lib/scripts/50unattended-upgrades $DEST/cache/sdcard/etc/apt/apt.conf.d/50unattended-upgrades
cp $SRC/lib/scripts/02periodic $DEST/cache/sdcard/etc/apt/apt.conf.d/02periodic

case $RELEASE in

# Debian Wheezy
wheezy)
		
		# add serial console
		echo T0:2345:respawn:/sbin/getty -L $SERIALCON 115200 vt100 >> $DEST/cache/sdcard/etc/inittab
		
		# don't clear screen on boot console
		sed -e 's/getty 38400 tty1/getty --noclear 38400 tty1/g' -i $DEST/cache/sdcard/etc/inittab
		
		# disable some getties
		sed -e 's/5:23:respawn/#5:23:respawn/g' -i $DEST/cache/sdcard/etc/inittab
		sed -e 's/6:23:respawn/#6:23:respawn/g' -i $DEST/cache/sdcard/etc/inittab
		
		# auto upgrading
		sed -e "s/ORIGIN/Debian/g" -i $DEST/cache/sdcard/etc/apt/apt.conf.d/50unattended-upgrades
		sed -e "s/n=CODENAME/a=old-stable/g" -i $DEST/cache/sdcard/etc/apt/apt.conf.d/50unattended-upgrades		
		
		# install ramlog
		cp $SRC/lib/bin/ramlog_2.0.0_all.deb $DEST/cache/sdcard/tmp
		chroot $DEST/cache/sdcard /bin/bash -c "dpkg -i /tmp/ramlog_2.0.0_all.deb >/dev/null 2>&1" 		
		# enabled back at first run. To remove errors
		chroot $DEST/cache/sdcard /bin/bash -c "service ramlog disable >/dev/null 2>&1"
		rm $DEST/cache/sdcard/tmp/ramlog_2.0.0_all.deb
		sed -e 's/TMPFS_RAMFS_SIZE=/TMPFS_RAMFS_SIZE=512m/g' -i $DEST/cache/sdcard/etc/default/ramlog
		sed -e 's/$remote_fs $time/$remote_fs $time ramlog/g' -i $DEST/cache/sdcard/etc/init.d/rsyslog 
		sed -e 's/umountnfs $time/umountnfs $time ramlog/g' -i $DEST/cache/sdcard/etc/init.d/rsyslog  
		;;

# Debian Jessie
jessie)
		
		# enable root login for latest ssh on jessie
		sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' $DEST/cache/sdcard/etc/ssh/sshd_config 
		
		# auto upgrading
		sed -e "s/ORIGIN/Debian/g" -i $DEST/cache/sdcard/etc/apt/apt.conf.d/50unattended-upgrades
		sed -e "s/CODENAME/$RELEASE/g" -i $DEST/cache/sdcard/etc/apt/apt.conf.d/50unattended-upgrades
		
		# mount 256Mb tmpfs to /tmp
		echo "tmpfs   /tmp         tmpfs   nodev,nosuid,size=256M          0  0" >> $DEST/cache/sdcard/etc/fstab
		
		# fix selinux error 
		mkdir $DEST/cache/sdcard/selinux
		
		# add serial console
		cp $SRC/lib/config/ttyS0.conf $DEST/cache/sdcard/etc/init/$SERIALCON.conf
		sed -e "s/ttyS0/$SERIALCON/g" -i $DEST/cache/sdcard/etc/init/$SERIALCON.conf
		chroot $DEST/cache/sdcard /bin/bash -c "systemctl --no-reload enable serial-getty@$SERIALCON.service >/dev/null 2>&1"
		mkdir -p "$DEST/cache/sdcard/etc/systemd/system/serial-getty@$SERIALCON.service.d"
		echo "[Service]" > "$DEST/cache/sdcard/etc/systemd/system/serial-getty@$SERIALCON.service.d/10-rate.conf"
		echo "ExecStart=" >> "$DEST/cache/sdcard/etc/systemd/system/serial-getty@$SERIALCON.service.d/10-rate.conf"
		echo "ExecStart=-/sbin/agetty -L 115200 %I $TERM" >> "$DEST/cache/sdcard/etc/systemd/system/serial-getty@$SERIALCON.service.d/10-rate.conf"

		# don't clear screen tty1
		mkdir -p "$DEST/cache/sdcard/etc/systemd/system/getty@tty1.service.d/"
		echo "[Service]" > "$DEST/cache/sdcard/etc/systemd/system/getty@tty1.service.d/10-noclear.conf"
		echo "TTYVTDisallocate=no" >> "$DEST/cache/sdcard/etc/systemd/system/getty@tty1.service.d/10-noclear.conf"
	
		# seting timeout
		mkdir -p $DEST/cache/sdcard/etc/systemd/system/systemd-modules-load.service.d/
		echo "[Service]" > $DEST/cache/sdcard/etc/systemd/system/systemd-modules-load.service.d/10-timeout.conf 
		echo "TimeoutStopSec=10" >> $DEST/cache/sdcard/etc/systemd/system/systemd-modules-load.service.d/10-timeout.conf		
		;;

# Ubuntu Trusty
trusty)
		
		# add serial console
		cp $SRC/lib/config/ttyS0.conf $DEST/cache/sdcard/etc/init/$SERIALCON.conf
		sed -e "s/ttyS0/$SERIALCON/g" -i $DEST/cache/sdcard/etc/init/$SERIALCON.conf

		# don't clear screen tty1
		sed -e s,"exec /sbin/getty","exec /sbin/getty --noclear",g 	-i $DEST/cache/sdcard/etc/init/tty1.conf
		
		# disable some getties
		rm -f $DEST/cache/sdcard/etc/init/tty5.conf
		rm -f $DEST/cache/sdcard/etc/init/tty6.conf
		
		# enable root login for latest ssh on trusty
		sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' $DEST/cache/sdcard/etc/ssh/sshd_config 		
		
		# fix selinux error 
		mkdir $DEST/cache/sdcard/selinux

		# that my custom motd works well
		if [ -d "$DEST/cache/sdcard/etc/update-motd.d" ]; then
			mv $DEST/cache/sdcard/etc/update-motd.d $DEST/cache/sdcard/etc/update-motd.d-backup
		fi

		# auto upgrading
		sed -e "s/ORIGIN/Ubuntu/g" -i $DEST/cache/sdcard/etc/apt/apt.conf.d/50unattended-upgrades
		sed -e "s/CODENAME/$RELEASE/g" -i $DEST/cache/sdcard/etc/apt/apt.conf.d/50unattended-upgrades

		# remove what's anyway not working 
		rm $DEST/cache/sdcard/etc/init/ureadahead*
		rm $DEST/cache/sdcard/etc/init/plymouth*
		;;

*) echo "Release hasn't been choosen"
exit
;;
esac

# copy hostapd configurations
install -m 755 $SRC/lib/config/hostapd.conf $DEST/cache/sdcard/etc/hostapd.conf 
install -m 755 $SRC/lib/config/hostapd.realtek.conf $DEST/cache/sdcard/etc/hostapd.conf-rt

# console fix due to Debian bug 
sed -e 's/CHARMAP=".*"/CHARMAP="'$CONSOLE_CHAR'"/g' -i $DEST/cache/sdcard/etc/default/console-setup

# root-fs modifications
rm 	-f $DEST/cache/sdcard/etc/motd
touch $DEST/cache/sdcard/etc/motd

# change time zone data
echo $TZDATA > $DEST/cache/sdcard/etc/timezone
chroot $DEST/cache/sdcard /bin/bash -c "dpkg-reconfigure -f noninteractive tzdata >/dev/null 2>&1"

# set root password 
chroot $DEST/cache/sdcard /bin/bash -c "(echo $ROOTPWD;echo $ROOTPWD;) | passwd root >/dev/null 2>&1"  

# create proper fstab
if [ "$BOOTSIZE" -eq "0" ]; then 
	local device="/dev/mmcblk0p1	/           ext4    defaults,noatime,nodiratime,data=writeback,commit=600,errors=remount-ro"
else
	local device="/dev/mmcblk0p2	/           ext4    defaults,noatime,nodiratime,data=writeback,commit=600,errors=remount-ro" 
fi
echo "$device        0       0" >> $DEST/cache/sdcard/etc/fstab

# flash media tunning
if [ -f "$DEST/cache/sdcard/etc/default/tmpfs" ]; then
	sed -e 's/#RAMTMP=no/RAMTMP=yes/g' -i $DEST/cache/sdcard/etc/default/tmpfs
	sed -e 's/#RUN_SIZE=10%/RUN_SIZE=128M/g' -i $DEST/cache/sdcard/etc/default/tmpfs 
	sed -e 's/#LOCK_SIZE=/LOCK_SIZE=/g' -i $DEST/cache/sdcard/etc/default/tmpfs 
	sed -e 's/#SHM_SIZE=/SHM_SIZE=128M/g' -i $DEST/cache/sdcard/etc/default/tmpfs 
	sed -e 's/#TMP_SIZE=/TMP_SIZE=1G/g' -i $DEST/cache/sdcard/etc/default/tmpfs
fi

# add custom bashrc loading
cat <<END >> $DEST/cache/sdcard/etc/bash.bashrc
if [ -f /etc/bash.bashrc.custom ]; then
    . /etc/bash.bashrc.custom
fi
END

# display welcome message at first root login
touch $DEST/cache/sdcard/root/.not_logged_in_yet

# remove hostapd because it's replaced with ours
chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y -qq remove hostapd >/dev/null 2>&1"
}
