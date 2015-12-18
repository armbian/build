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

case $RELEASE in

# Debian Wheezy
wheezy)
		
		# specifics packets
		install_packet "libnl-dev" "Installing Wheezy packages" "" "quiet"
		
		# add serial console
		echo T0:2345:respawn:/sbin/getty -L ttyS0 115200 vt100 >> $DEST/cache/sdcard/etc/inittab
		
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

		# specifics packets add and remove
		install_packet "thin-provisioning-tools libnl-3-dev libnl-genl-3-dev libpam-systemd \
		software-properties-common python-software-properties libnss-myhostname" "Installing Jessie packages" "" "quiet"
		
		LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/cache/sdcard /bin/bash -c "apt-get autoremove >/dev/null 2>&1"
		
		# enable root login for latest ssh on jessie
		sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' $DEST/cache/sdcard/etc/ssh/sshd_config 
		
		# auto upgrading
		sed -e "s/ORIGIN/Debian/g" -i $DEST/cache/sdcard/etc/apt/apt.conf.d/50unattended-upgrades
		sed -e "s/CODENAME/$RELEASE/g" -i $DEST/cache/sdcard/etc/apt/apt.conf.d/50unattended-upgrades
		
		# mount 256Mb tmpfs to /tmp
		echo "tmpfs   /tmp         tmpfs   nodev,nosuid,size=256M          0  0" >> $DEST/cache/sdcard/etc/fstab
		
		# fix selinux error 
		chroot $DEST/cache/sdcard /bin/bash -c "mkdir /selinux"
				
		# configuration for systemd
		
		# add serial console
		local systemdpath="$DEST/cache/sdcard/lib/systemd/system"
		cp $SRC/lib/config/ttyS0.conf $DEST/cache/sdcard/etc/init/ttyS0.conf
		cp $systemdpath/serial-getty@.service $systemdpath/getty.target.wants/serial-getty@ttyS0.service
		sed -e s/"--keep-baud 115200,38400,9600"/"-L 115200"/g -i $systemdpath/getty.target.wants/serial-getty@ttyS0.service
		
		# don't clear screen tty1
		sed -e s,"TTYVTDisallocate=yes","TTYVTDisallocate=no",g -i $DEST/cache/sdcard/lib/systemd/system/getty@.service
		
		# configuration for sysvinit
				
		# add serial console
		echo T0:2345:respawn:/sbin/getty -L ttyS0 115200 vt100 >> $DEST/cache/sdcard/etc/inittab
		
		# don't clear screen on boot console
		sed -e 's/getty 38400 tty1/getty --noclear 38400 tty1/g' -i $DEST/cache/sdcard/etc/inittab
		
		# disable some getties
		sed -e 's/5:23:respawn/#5:23:respawn/g' -i $DEST/cache/sdcard/etc/inittab
		sed -e 's/6:23:respawn/#6:23:respawn/g' -i $DEST/cache/sdcard/etc/inittab		
		;;

# Ubuntu Trusty
trusty)

		# specifics packets add and remove
		install_packet "libnl-3-dev libnl-genl-3-dev software-properties-common \
		python-software-properties" "Installing Trusty packages" "" "quiet"
		
		LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/cache/sdcard /bin/bash -c "apt-get autoremove >/dev/null 2>&1"
		
		# add serial console
		cp $SRC/lib/config/ttyS0.conf $DEST/cache/sdcard/etc/init/ttyS0.conf

		# don't clear screen tty1
		sed -e s,"exec /sbin/getty","exec /sbin/getty --noclear",g 	-i $DEST/cache/sdcard/etc/init/tty1.conf
		
		# disable some getties
		chroot $DEST/cache/sdcard /bin/bash -c "rm /etc/init/tty5.conf"
		chroot $DEST/cache/sdcard /bin/bash -c "rm /etc/init/tty6.conf"
		
		# enable root login for latest ssh on trusty
		sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' $DEST/cache/sdcard/etc/ssh/sshd_config 		
		
		# fix selinux error 
		chroot $DEST/cache/sdcard /bin/bash -c "mkdir /selinux"

		# that my custom motd works well
		if [ -d "$DEST/cache/sdcard/etc/update-motd.d" ]; then
			chroot $DEST/cache/sdcard /bin/bash -c "mv /etc/update-motd.d /etc/update-motd.d-backup"
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

# Common

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

# remove hostapd because it's replaced with ours
chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y -qq remove hostapd >/dev/null 2>&1"
}