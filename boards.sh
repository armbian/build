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


mount_debian_template (){
#--------------------------------------------------------------------------------------------------------------------------------
# Mount prepared root file-system
#--------------------------------------------------------------------------------------------------------------------------------
if [ ! -f "$DEST/output/kernel/"$CHOOSEN_KERNEL ]; then 
	echo "Previously compiled kernel does not exits. Please choose compile=yes in configuration and run again!"
	exit 
fi
mkdir -p $DEST/output/sdcard/
gzip -dc < $DEST/output/rootfs/$RELEASE.raw.gz > $DEST/output/debian_rootfs.raw
LOOP=$(losetup -f)
losetup -o 1048576 $LOOP $DEST/output/debian_rootfs.raw
mount -t ext4 $LOOP $DEST/output/sdcard/

# relabel 
e2label $LOOP "$BOARD"

# mount proc, sys and dev
mount -t proc chproc $DEST/output/sdcard/proc
mount -t sysfs chsys $DEST/output/sdcard/sys
mount -t devtmpfs chdev $DEST/output/sdcard/dev || mount --bind /dev $DEST/output/sdcard/dev
mount -t devpts chpts $DEST/output/sdcard/dev/pts
}


install_board_specific (){
#--------------------------------------------------------------------------------------------------------------------------------
# Install board common and specific applications
#--------------------------------------------------------------------------------------------------------------------------------
echo "------ Install board common applications"

case $RELEASE in
#--------------------------------------------------------------------------------------------------------------------------------

wheezy)
		# specifics packets
		LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/output/sdcard /bin/bash -c "apt-get -y install libnl-dev"
		# add serial console
		echo T0:2345:respawn:/sbin/getty -L ttyS0 115200 vt100 >> $DEST/output/sdcard/etc/inittab
		# don't clear screen on boot console
		sed -e 's/1:2345:respawn:\/sbin\/getty 38400 tty1/1:2345:respawn:\/sbin\/getty --noclear 38400 tty1/g' -i $DEST/output/sdcard/etc/inittab
		# disable some getties
		sed -e 's/3:23:respawn/#3:23:respawn/g' -i $DEST/output/sdcard/etc/inittab
		sed -e 's/4:23:respawn/#4:23:respawn/g' -i $DEST/output/sdcard/etc/inittab
		sed -e 's/5:23:respawn/#5:23:respawn/g' -i $DEST/output/sdcard/etc/inittab
		sed -e 's/6:23:respawn/#6:23:respawn/g' -i $DEST/output/sdcard/etc/inittab
		# auto upgrading
		sed -e "s/ORIGIN/Debian/g" -i $DEST/output/sdcard/etc/apt/apt.conf.d/50unattended-upgrades
		# install ramlog
		cp $SRC/lib/bin/ramlog_2.0.0_all.deb $DEST/output/sdcard/tmp
		chroot $DEST/output/sdcard /bin/bash -c "dpkg -i /tmp/ramlog_2.0.0_all.deb"
		# enabled back at first run. To remove errors
		chroot $DEST/output/sdcard /bin/bash -c "service ramlog disable"
		rm $DEST/output/sdcard/tmp/ramlog_2.0.0_all.deb
		sed -e 's/TMPFS_RAMFS_SIZE=/TMPFS_RAMFS_SIZE=512m/g' -i $DEST/output/sdcard/etc/default/ramlog
		sed -e 's/# Required-Start:    $remote_fs $time/# Required-Start:    $remote_fs $time ramlog/g' -i $DEST/output/sdcard/etc/init.d/rsyslog 
		sed -e 's/# Required-Stop:     umountnfs $time/# Required-Stop:     umountnfs $time ramlog/g' -i $DEST/output/sdcard/etc/init.d/rsyslog  
		;;
jessie)
		# add serial console
		cp $SRC/lib/config/ttyS0.conf $DEST/output/sdcard/etc/init/ttyS0.conf
		cp $DEST/output/sdcard/lib/systemd/system/serial-getty@.service $DEST/output/sdcard/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service
		sed -e s/"--keep-baud 115200,38400,9600"/"-L 115200"/g  -i $DEST/output/sdcard/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service
		# specifics packets add and remove
		LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/output/sdcard /bin/bash -c "apt-get -y install libnl-3-dev libnl-genl-3-dev busybox-syslogd software-properties-common python-software-properties"
		LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/output/sdcard /bin/bash -c "apt-get autoremove"
		# don't clear screen tty1
		sed -e s,"TTYVTDisallocate=yes","TTYVTDisallocate=no",g 	-i $DEST/output/sdcard/lib/systemd/system/getty@.service
		# enable root login for latest ssh on jessie
		sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' $DEST/output/sdcard/etc/ssh/sshd_config 
		# auto upgrading
		sed -e "s/ORIGIN/Debian/g" -i $DEST/output/sdcard/etc/apt/apt.conf.d/50unattended-upgrades
		;;
trusty)
		# add serial console
		cp $SRC/lib/config/ttyS0.conf $DEST/output/sdcard/etc/init/ttyS0.conf
		cp $DEST/output/sdcard/lib/systemd/system/serial-getty@.service $DEST/output/sdcard/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service
		sed -e s/"--keep-baud 115200,38400,9600"/"-L 115200"/g  -i $DEST/output/sdcard/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service
		# specifics packets add and remove
		LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/output/sdcard /bin/bash -c "apt-get -y install libnl-3-dev libnl-genl-3-dev busybox-syslogd software-properties-common python-software-properties"
		LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/output/sdcard /bin/bash -c "apt-get autoremove"		
		# don't clear screen tty1
		sed -e s,"TTYVTDisallocate=yes","TTYVTDisallocate=no",g 	-i $DEST/output/sdcard/lib/systemd/system/getty@.service
		# enable root login for latest ssh on trusty
		sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' $DEST/output/sdcard/etc/ssh/sshd_config 		
		# that my startup scripts works well
		if [ ! -f "$DEST/output/sdcard/sbin/insserv" ]; then
			chroot $DEST/output/sdcard /bin/bash -c "ln -s /usr/lib/insserv/insserv /sbin/insserv"
		fi
		# that my custom motd works well
		if [ -d "$DEST/output/sdcard/etc/update-motd.d" ]; then
			chroot $DEST/output/sdcard /bin/bash -c "mv /etc/update-motd.d /etc/update-motd.d-backup"
		fi
		# auto upgrading
		sed -e "s/ORIGIN/Ubuntu/g" -i $DEST/output/sdcard/etc/apt/apt.conf.d/50unattended-upgrades
		# remove what's anyway not working 
		rm $DEST/output/sdcard/etc/init/ureadahead*
		rm $DEST/output/sdcard/etc/init/plymouth*
		;;
*) echo "Relese hasn't been choosen"
exit
;;
esac
#--------------------------------------------------------------------------------------------------------------------------------

# change time zone data
echo $TZDATA > $DEST/output/sdcard/etc/timezone
chroot $DEST/output/sdcard /bin/bash -c "dpkg-reconfigure -f noninteractive tzdata >/dev/null 2>&1"

# set root password and force password change upon first login
chroot $DEST/output/sdcard /bin/bash -c "(echo $ROOTPWD;echo $ROOTPWD;) | passwd root >/dev/null 2>&1"  
chroot $DEST/output/sdcard /bin/bash -c "chage -d 0 root" 

# add noatime to root FS
echo "/dev/mmcblk0p1  /           ext4    defaults,noatime,nodiratime,data=writeback,commit=600,errors=remount-ro        0       0" >> $DEST/output/sdcard/etc/fstab

# flash media tunning
if [ -f "$DEST/output/sdcard/etc/default/tmpfs" ]; then
	sed -e 's/#RAMTMP=no/RAMTMP=yes/g' -i $DEST/output/sdcard/etc/default/tmpfs
	sed -e 's/#RUN_SIZE=10%/RUN_SIZE=128M/g' -i $DEST/output/sdcard/etc/default/tmpfs 
	sed -e 's/#LOCK_SIZE=/LOCK_SIZE=/g' -i $DEST/output/sdcard/etc/default/tmpfs 
	sed -e 's/#SHM_SIZE=/SHM_SIZE=128M/g' -i $DEST/output/sdcard/etc/default/tmpfs 
	sed -e 's/#TMP_SIZE=/TMP_SIZE=1G/g' -i $DEST/output/sdcard/etc/default/tmpfs
fi

# create .deb package for the rest
#
CHOOSEN_ROOTFS=linux-"$RELEASE"-root-"$BOARD"_"$REVISION"_armhf
mkdir -p $DEST/output/rootfs/$CHOOSEN_ROOTFS/DEBIAN
cat <<END > $DEST/output/rootfs/$CHOOSEN_ROOTFS/DEBIAN/control
Package: linux-$RELEASE-root-$BOARD
Version: $REVISION
Architecture: all
Maintainer: $MAINTAINER <$MAINTAINERMAIL>
Installed-Size: 1
Section: kernel
Priority: optional
Description: Various root file system tweaks for ARM boards
END
#
# set up post install script
echo "#!/bin/bash" > $DEST/output/rootfs/$CHOOSEN_ROOTFS/DEBIAN/postinst
chmod 755 $DEST/output/rootfs/$CHOOSEN_ROOTFS/DEBIAN/postinst

# scripts for autoresize at first boot
mkdir -p $DEST/output/rootfs/$CHOOSEN_ROOTFS/etc/init.d
mkdir -p $DEST/output/rootfs/$CHOOSEN_ROOTFS/etc/default
install -m 755 $SRC/lib/scripts/resize2fs $DEST/output/rootfs/$CHOOSEN_ROOTFS/etc/init.d
install -m 755 $SRC/lib/scripts/firstrun  $DEST/output/rootfs/$CHOOSEN_ROOTFS/etc/init.d

# install custom bashrc and hardware dependent motd
cat <<END >> $DEST/output/sdcard/etc/bash.bashrc
if [ -f /etc/bash.bashrc.custom ]; then
    . /etc/bash.bashrc.custom
fi
END
install $SRC/lib/scripts/bashrc $DEST/output/rootfs/$CHOOSEN_ROOTFS/etc/bash.bashrc.custom
install -m 755 $SRC/lib/scripts/armhwinfo $DEST/output/rootfs/$CHOOSEN_ROOTFS/etc/init.d 
echo "insserv armhwinfo" >> $DEST/output/rootfs/$CHOOSEN_ROOTFS/DEBIAN/postinst
echo "insserv firstrun" >> $DEST/output/rootfs/$CHOOSEN_ROOTFS/DEBIAN/postinst
echo "insserv -rf motd >/dev/null 2>&1" >> $DEST/output/rootfs/$CHOOSEN_ROOTFS/DEBIAN/postinst

# temper binary for USB temp meter
mkdir -p $DEST/output/rootfs/$CHOOSEN_ROOTFS/usr/local/bin
tar xfz $SRC/lib/bin/temper.tgz -C $DEST/output/rootfs/$CHOOSEN_ROOTFS/usr/local/bin

# replace hostapd from latest self compiled & patched
chroot $DEST/output/sdcard /bin/bash -c "apt-get -y remove hostapd"
mkdir -p $DEST/output/rootfs/$CHOOSEN_ROOTFS/usr/sbin/
tar xfz $SRC/lib/bin/hostapd25-rt.tgz -C $DEST/output/rootfs/$CHOOSEN_ROOTFS/usr/sbin/
install -m 755 $SRC/lib/config/hostapd.realtek.conf $DEST/output/rootfs/$CHOOSEN_ROOTFS/etc/hostapd.conf-rt

tar xfz $SRC/lib/bin/hostapd25.tgz -C $DEST/output/rootfs/$CHOOSEN_ROOTFS/usr/sbin/
install -m 755 $SRC/lib/config/hostapd.conf $DEST/output/rootfs/$CHOOSEN_ROOTFS/etc/hostapd.conf 

# alter hostap configuration
sed -i "s/BOARD/$BOARD/" $DEST/output/rootfs/$CHOOSEN_ROOTFS/etc/hostapd.conf
 
# script to install to SATA
mkdir -p $DEST/output/rootfs/$CHOOSEN_ROOTFS/root
install -m 755 $SRC/lib/scripts/nand-sata-install $DEST/output/rootfs/$CHOOSEN_ROOTFS/root/nand-sata-install



echo "------ Install board specific applications"

# allwinner 
if [[ $LINUXCONFIG == *sunxi* ]] ; then

	# add sunxi tools
	cp $DEST/sunxi-tools/fex2bin $DEST/sunxi-tools/bin2fex $DEST/sunxi-tools/nand-part $DEST/output/rootfs/$CHOOSEN_ROOTFS/usr/local/bin

	# lamobo R1 router switch config
	tar xfz $SRC/lib/bin/swconfig.tgz -C $DEST/output/rootfs/$CHOOSEN_ROOTFS/usr/local/bin

	# add NAND boot content
	if [[ $BOARD != "bananapi" ]] ; then
		mkdir -p $DEST/output/rootfs/$CHOOSEN_ROOTFS/root
		cp $SRC/lib/bin/nand1-allwinner.tgz $DEST/output/rootfs/$CHOOSEN_ROOTFS/root
	fi
	
	# convert and add fex files
	mkdir -p $DEST/output/rootfs/$CHOOSEN_ROOTFS/boot/bin
	for i in $(ls -w1 $SRC/lib/config/*.fex | xargs -n1 basename); do fex2bin $SRC/lib/config/${i%*.fex}.fex $DEST/output/rootfs/$CHOOSEN_ROOTFS/boot/bin/${i%*.fex}.bin; done
	
	# bluetooth device enabler - for cubietruck
	install -m 755	$SRC/lib/bin/brcm_patchram_plus		$DEST/output/rootfs/$CHOOSEN_ROOTFS/usr/local/bin
	install			$SRC/lib/scripts/brcm40183 			$DEST/output/rootfs/$CHOOSEN_ROOTFS/etc/default
	install -m 755  $SRC/lib/scripts/brcm40183-patch    $DEST/output/rootfs/$CHOOSEN_ROOTFS/etc/init.d
	
	# default lirc configuration
	sed -i '1i sed -i \x27s/DEVICE="\\/dev\\/input.*/DEVICE="\\/dev\\/input\\/\x27$str\x27"/g\x27 /etc/lirc/hardware.conf' $DEST/output/sdcard/etc/lirc/hardware.conf
	sed -i '1i str=$(cat /proc/bus/input/devices | grep "H: Handlers=sysrq rfkill kbd event" | awk \x27{print $(NF)}\x27)' $DEST/output/sdcard/etc/lirc/hardware.conf
	sed -i '1i # Cubietruck automatic lirc device detection by Igor Pecovnik' $DEST/output/sdcard/etc/lirc/hardware.conf
	sed -e 's/DEVICE=""/DEVICE="\/dev\/input\/event1"/g' -i $DEST/output/sdcard/etc/lirc/hardware.conf
	sed -e 's/DRIVER="UNCONFIGURED"/DRIVER="devinput"/g' -i $DEST/output/sdcard/etc/lirc/hardware.conf
	cp $SRC/lib/config/lirc.conf.cubietruck $DEST/output/sdcard/etc/lirc/lircd.conf

fi # allwinner

if [[ $BOARD == udoo* ]] ; then		
		if [ -f $DEST/output/sdcard/etc/inittab ]; then sed -e "s/ttyS0/ttymxc1/g" -i $DEST/output/sdcard/etc/inittab; fi
		if [ -f $DEST/output/sdcard/etc/init/ttyS0.conf ]; then mv $DEST/output/sdcard/etc/init/ttyS0.conf $DEST/output/sdcard/etc/init/ttymxc1.conf; sed -e "s/ttymxc1/ttyS0/g" -i $DEST/output/sdcard/etc/init/ttymxc1.conf; fi	
		chroot $DEST/output/sdcard /bin/bash -c "apt-get -y -qq remove lirc && apt-get -y -qq autoremove"		
		sed 's/wlan0/wlan2/' -i $DEST/output/sdcard/etc/network/interfaces.default
		sed 's/wlan0/wlan2/' -i $DEST/output/sdcard/etc/network/interfaces.bonding
		sed 's/wlan0/wlan2/' -i $DEST/output/sdcard/etc/network/interfaces.hostapd
		# Udoo doesn't have interactive 		
		sed -e 's/interactive/ondemand/g' -i $DEST/output/sdcard/etc/init.d/cpufrequtils
fi

if [[ $BOARD == cubox-i* ]] ; then
		if [ -f $DEST/output/sdcard/etc/inittab ]; then sed -e "s/ttyS0/ttymxc0/g" -i $DEST/output/sdcard/etc/inittab; fi
		if [ -f $DEST/output/sdcard/etc/init/ttyS0.conf ]; then mv $DEST/output/sdcard/etc/init/ttyS0.conf $DEST/output/sdcard/etc/init/ttymxc0.conf; sed -e "s/ttymxc0/ttyS0/g" -i $DEST/output/sdcard/etc/init/ttymxc0.conf; fi	
		
		# default lirc configuration 
		sed -e 's/DEVICE=""/DEVICE="\/dev\/lirc0"/g' -i $DEST/output/sdcard/etc/lirc/hardware.conf
		sed -e 's/DRIVER="UNCONFIGURED"/DRIVER="default"/g' -i $DEST/output/sdcard/etc/lirc/hardware.conf
		cp $SRC/lib/config/lirc.conf.cubox-i $DEST/output/sdcard/etc/lirc/lircd.conf
		cp $SRC/lib/bin/brcm_patchram_plus_cubox $DEST/output/sdcard/usr/local/bin/brcm_patchram_plus
		chroot $DEST/output/sdcard /bin/bash -c "chmod +x /usr/local/bin/brcm_patchram_plus"
		cp $SRC/lib/scripts/brcm4330 $DEST/output/sdcard/etc/default
		cp $SRC/lib/scripts/brcm4330-patch $DEST/output/sdcard/etc/init.d
		chroot $DEST/output/sdcard /bin/bash -c "chmod +x /etc/init.d/brcm4330-patch"
		chroot $DEST/output/sdcard /bin/bash -c "insserv brcm4330-patch >> /dev/null" 
		case $RELEASE in
		wheezy)
		echo "deb http://repo.gbps.io/BSP:/Cubox-i/Debian_Wheezy/ ./" >> $DEST/output/sdcard/etc/apt/sources.list
		cp $SRC/lib/scripts/mxobs $DEST/output/sdcard/etc/apt/preferences.d/mxobs
		mkdir $DEST/output/sdcard/etc/X11/
		cp $SRC/lib/config/xorg.conf.cubox $DEST/output/sdcard/etc/X11/xorg.conf
		chroot $DEST/output/sdcard /bin/bash -c "wget -qO - http://repo.gbps.io/BSP:/Cubox-i:/devel/Debian_Wheezy/Release.key | apt-key add -"
		;;
		jessie)
		echo "deb http://repo.gbps.io/BSP:/Cubox-i/Debian_Jessie/ ./" >> $DEST/output/sdcard/etc/apt/sources.list
		chroot $DEST/output/sdcard /bin/bash -c "wget -qO - http://repo.gbps.io/BSP:/Cubox-i:/devel/Debian_Wheezy/Release.key | apt-key add -"
		;;
		trusty)
		echo "deb http://repo.gbps.io/BSP:/Cubox-i/Ubuntu_Trusty_Tahr/ ./" >> $DEST/output/sdcard/etc/apt/sources.list
		chroot $DEST/output/sdcard /bin/bash -c "wget -qO - http://repo.gbps.io/BSP:/Cubox-i/Ubuntu_Trusty_Tahr/Release.key | apt-key add -"
		;;
		esac
fi
cd $DEST/output/rootfs/
dpkg -b $CHOOSEN_ROOTFS
rm -rf $CHOOSEN_ROOTFS
# install custom root package 
cp $CHOOSEN_ROOTFS.deb /tmp/kernel
chroot $DEST/output/sdcard /bin/bash -c "dpkg -i /tmp/$CHOOSEN_ROOTFS.deb"

# add deb file to common tar
# tar -uf $DEST"/output/kernel/"$CHOOSEN_KERNEL"-""$BRANCH"".tar" $CHOOSEN_ROOTFS.deb
echo "------ done."
}


install_kernel (){
#--------------------------------------------------------------------------------------------------------------------------------
# Install kernel to prepared root file-system
#--------------------------------------------------------------------------------------------------------------------------------
echo -e "[\e[0;32m ok \x1B[0m] Install kernel"
#echo "------ Install kernel"

# configure MIN / MAX speed for cpufrequtils
sed -e "s/MIN_SPEED=\"0\"/MIN_SPEED=\"$CPUMIN\"/g" -i $DEST/output/sdcard/etc/init.d/cpufrequtils
sed -e "s/MAX_SPEED=\"0\"/MAX_SPEED=\"$CPUMAX\"/g" -i $DEST/output/sdcard/etc/init.d/cpufrequtils
sed -e 's/ondemand/interactive/g' -i $DEST/output/sdcard/etc/init.d/cpufrequtils

# set hostname 
echo $HOST > $DEST/output/sdcard/etc/hostname

# set hostname in hosts file
cat > $DEST/output/sdcard/etc/hosts <<EOT
127.0.0.1   localhost $HOST
::1         localhost $HOST ip6-localhost ip6-loopback
fe00::0     ip6-localnet
ff00::0     ip6-mcastprefix
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOT

# create modules file
if [[ $BRANCH == *next* ]];then
for word in $MODULES_NEXT; do echo $word >> $DEST/output/sdcard/etc/modules; done
else
for word in $MODULES; do echo $word >> $DEST/output/sdcard/etc/modules; done
fi

# copy and create symlink to default interfaces configuration
cp $SRC/lib/config/interfaces.* $DEST/output/sdcard/etc/network/
ln -sf interfaces.default $DEST/output/sdcard/etc/network/interfaces

# install kernel
rm -rf /tmp/kernel && mkdir -p /tmp/kernel && cd /tmp/kernel
tar -xPf $DEST"/output/kernel/"$CHOOSEN_KERNEL
mount --bind /tmp/kernel/ $DEST/output/sdcard/tmp
chroot $DEST/output/sdcard /bin/bash -c "dpkg -i /tmp/*u-boot*.deb"
chroot $DEST/output/sdcard /bin/bash -c "dpkg -i /tmp/*image*.deb"
chroot $DEST/output/sdcard /bin/bash -c "dpkg -i /tmp/*headers*.deb"
if [[ $BRANCH == *next* || $LINUXSOURCE == "linux-cubox" ]];then
	chroot $DEST/output/sdcard /bin/bash -c "dpkg -i /tmp/*dtb*.deb"
fi
# name of archive is also kernel name
CHOOSEN_KERNEL="${CHOOSEN_KERNEL//-$BRANCH.tar/}"

echo "------ Compile headers scripts"

# patch scripts
cd $DEST/output/sdcard/usr/src/linux-headers-$CHOOSEN_KERNEL
patch -p1 < $SRC/lib/patch/headers-debian-byteshift.patch
# recompile headers scripts
chroot $DEST/output/sdcard /bin/bash -c "cd /usr/src/linux-headers-$CHOOSEN_KERNEL && make headers_check; make headers_install ; make scripts"

# recreate boot.scr if using kernel for different board. Mainline only
if [[ $BRANCH == *next* || $BOARD == cubox-i* ]];then
		# remove .old on new image
		rm -rf $DEST/output/sdcard/boot/dtb.old
		# copy boot script and change it acordingly
		if [[ $BOARD == udoo* ]] ; then		
			cp $SRC/lib/config/boot-udoo-next.cmd $DEST/output/sdcard/boot/boot-next.cmd
		elif [[ $BOARD == cubox-i* ]]; then
			cp $SRC/lib/config/boot-cubox.cmd $DEST/output/sdcard/boot/boot-next.cmd
		else
			cp $SRC/lib/config/boot.cmd $DEST/output/sdcard/boot/boot.cmd
			mkimage -C none -A arm -T script -d $SRC/lib/config/boot.cmd $DEST/output/sdcard/boot/boot.scr >> /dev/null
		fi
		#sed -e "s/zImage/vmlinuz-$CHOOSEN_KERNEL/g" -i $DEST/output/sdcard/boot/boot-next.cmd
		#chroot $DEST/output/sdcard /bin/bash -c "ln -s /boot/vmlinuz-$CHOOSEN_KERNEL /boot/zImage"
		#sed -e "s/dtb/dtb\/$CHOOSEN_KERNEL/g" -i $DEST/output/sdcard/boot/boot-next.cmd
		# compile boot script
		
	elif [[ $LINUXCONFIG == *sunxi* ]]; then
		chroot $DEST/output/sdcard /bin/bash -c "ln -s /boot/bin/$BOARD.bin /boot/script.bin"
		cp $SRC/lib/config/boot.cmd $DEST/output/sdcard/boot/boot.cmd
		# compile boot script
		mkimage -C none -A arm -T script -d $DEST/output/sdcard/boot/boot.cmd $DEST/output/sdcard/boot/boot.scr >> /dev/null
	else
		# make symlink to kernel and uImage
		mkimage -A arm -O linux -T kernel -C none -a "0x40008000" -e "0x10008000" -n "Linux kernel" -d $DEST/output/sdcard/boot/vmlinuz-$CHOOSEN_KERNEL $DEST/output/sdcard/boot/uImage
		chroot $DEST/output/sdcard /bin/bash -c "ln -s /boot/vmlinuz-$CHOOSEN_KERNEL /boot/zImage"
fi

# add linux firmwares to output image
unzip -q $SRC/lib/bin/linux-firmware.zip -d $DEST/output/sdcard/lib/firmware
}


install_desktop (){
#--------------------------------------------------------------------------------------------------------------------------------
# Install desktop with HW acceleration
#--------------------------------------------------------------------------------------------------------------------------------
echo "------ Install desktop"
chroot $DEST/output/sdcard /bin/bash -c "debconf-apt-progress -- apt-get -y install xorg lightdm xfce4 xfce4-goodies tango-icon-theme gnome-icon-theme"
if [[ $LINUXCONFIG == *sunxi* ]]; then
 chroot $DEST/output/sdcard /bin/bash -c "debconf-apt-progress -- apt-get -y install xorg-dev xutils-dev x11proto-dri2-dev"
 chroot $DEST/output/sdcard /bin/bash -c "debconf-apt-progress -- apt-get -y install libltdl-dev libtool automake libdrm-dev"
 # quemu bug walkaround
 git clone https://github.com/ssvb/xf86-video-fbturbo.git $DEST/output/sdcard/tmp/xf86-video-fbturbo
 chroot $DEST/output/sdcard /bin/bash -c "cd /tmp/xf86-video-fbturbo && autoreconf -vi"
 chroot $DEST/output/sdcard /bin/bash -c "cd /tmp/xf86-video-fbturbo && ./configure --prefix=/usr"
 chroot $DEST/output/sdcard /bin/bash -c "cd /tmp/xf86-video-fbturbo && make && make install && cp xorg.conf /etc/X11/xorg.conf"
 # clean deb cache
 chroot $DEST/output/sdcard /bin/bash -c "apt-get -y clean"	
fi
}