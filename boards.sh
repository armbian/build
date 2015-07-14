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


install_board_specific (){
#--------------------------------------------------------------------------------------------------------------------------------
# Install board common and specific applications
#--------------------------------------------------------------------------------------------------------------------------------
echo -e "[\e[0;32m ok \x1B[0m] Install board specific applications"

# Allwinner
if [[ $LINUXCONFIG == *sunxi* ]] ; then

	# add sunxi tools
	cp $DEST/sunxi-tools/fex2bin $DEST/sunxi-tools/bin2fex $DEST/sunxi-tools/nand-part $DEST/output/rootfs/$CHOOSEN_ROOTFS/usr/local/bin

	# lamobo R1 router switch config
	tar xfz $SRC/lib/bin/swconfig.tgz -C $DEST/output/rootfs/$CHOOSEN_ROOTFS/usr/local/bin

	# add NAND boot content
	mkdir -p $DEST/output/rootfs/$CHOOSEN_ROOTFS/root
	cp $SRC/lib/bin/nand1-allwinner.tgz $DEST/output/rootfs/$CHOOSEN_ROOTFS/root/.nand1-allwinner.tgz
	
	# convert and add fex files
	mkdir -p $DEST/output/rootfs/$CHOOSEN_ROOTFS/boot/bin
	for i in $(ls -w1 $SRC/lib/config/*.fex | xargs -n1 basename); 
		do fex2bin $SRC/lib/config/${i%*.fex}.fex $DEST/output/rootfs/$CHOOSEN_ROOTFS/boot/bin/${i%*.fex}.bin; 
	done
	
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

fi 

# udoo
if [[ $BOARD == "udoo" ]] ; then		
		if [ -f $DEST/output/sdcard/etc/inittab ]; then sed -e "s/ttyS0/ttymxc1/g" -i $DEST/output/sdcard/etc/inittab; fi
		if [ -f $DEST/output/sdcard/etc/init/ttyS0.conf ]; then 
			mv $DEST/output/sdcard/etc/init/ttyS0.conf $DEST/output/sdcard/etc/init/ttymxc1.conf; 
			sed -e "s/ttyS0/ttymxc1/g" -i $DEST/output/sdcard/etc/init/ttymxc1.conf; 
		fi
		if [ -f $DEST/output/sdcard/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service ]; then mv $DEST/output/sdcard/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service  $DEST/output/sdcard/etc/systemd/system/getty.target.wants/serial-getty@ttymxc1.service ; fi
		chroot $DEST/output/sdcard /bin/bash -c "apt-get -y -qq remove lirc && apt-get -y -qq autoremove"		
		sed 's/wlan0/wlan2/' -i $DEST/output/sdcard/etc/network/interfaces.default
		sed 's/wlan0/wlan2/' -i $DEST/output/sdcard/etc/network/interfaces.bonding
		sed 's/wlan0/wlan2/' -i $DEST/output/sdcard/etc/network/interfaces.hostapd
		# Udoo doesn't have interactive 		
		sed -e 's/interactive/ondemand/g' -i $DEST/output/sdcard/etc/init.d/cpufrequtils
fi

# udoo neo
if [[ $BOARD == "udoo-neo" ]] ; then		
		if [ -f $DEST/output/sdcard/etc/inittab ]; then sed -e "s/ttyS0/ttymxc0/g" -i $DEST/output/sdcard/etc/inittab; fi
		if [ -f $DEST/output/sdcard/etc/init/ttyS0.conf ]; then mv $DEST/output/sdcard/etc/init/ttyS0.conf $DEST/output/sdcard/etc/init/ttymxc0.conf; sed -e "s/ttyS0/ttymxc0/g" -i $DEST/output/sdcard/etc/init/ttymxc0.conf; fi	
		if [ -f $DEST/output/sdcard/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service ]; then mv $DEST/output/sdcard/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service  $DEST/output/sdcard/etc/systemd/system/getty.target.wants/serial-getty@ttymxc0.service ; fi
		chroot $DEST/output/sdcard /bin/bash -c "apt-get -y -qq remove lirc && apt-get -y -qq autoremove"		
		sed 's/wlan0/wlan2/' -i $DEST/output/sdcard/etc/network/interfaces.default
		sed 's/wlan0/wlan2/' -i $DEST/output/sdcard/etc/network/interfaces.bonding
		sed 's/wlan0/wlan2/' -i $DEST/output/sdcard/etc/network/interfaces.hostapd
		# SD card is elsewhere
		sed 's/mmcblk0p1/mmcblk1p1/' -i $DEST/output/sdcard/etc/fstab
fi

# cubox / hummingboard
if [[ $BOARD == cubox-i* ]] ; then
		if [ -f $DEST/output/sdcard/etc/inittab ]; then sed -e "s/ttyS0/ttymxc0/g" -i $DEST/output/sdcard/etc/inittab; fi
		if [ -f $DEST/output/sdcard/etc/init/ttyS0.conf ]; then mv $DEST/output/sdcard/etc/init/ttyS0.conf $DEST/output/sdcard/etc/init/ttymxc0.conf; sed -e "s/ttyS0/ttymxc0/g" -i $DEST/output/sdcard/etc/init/ttymxc0.conf; fi	
		if [ -f $DEST/output/sdcard/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service ]; then mv $DEST/output/sdcard/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service  $DEST/output/sdcard/etc/systemd/system/getty.target.wants/serial-getty@ttymxc0.service ; fi
		
		# default lirc configuration 
		sed -e 's/DEVICE=""/DEVICE="\/dev\/lirc0"/g' -i $DEST/output/sdcard/etc/lirc/hardware.conf
		sed -e 's/DRIVER="UNCONFIGURED"/DRIVER="default"/g' -i $DEST/output/sdcard/etc/lirc/hardware.conf
		cp $SRC/lib/config/lirc.conf.cubox-i $DEST/output/sdcard/etc/lirc/lircd.conf
		cp $SRC/lib/bin/brcm_patchram_plus_cubox $DEST/output/sdcard/usr/local/bin/brcm_patchram_plus
		chroot $DEST/output/sdcard /bin/bash -c "chmod +x /usr/local/bin/brcm_patchram_plus"
		cp $SRC/lib/scripts/brcm4330 $DEST/output/sdcard/etc/default
		cp $SRC/lib/scripts/brcm4330-patch $DEST/output/sdcard/etc/init.d
		chroot $DEST/output/sdcard /bin/bash -c "chmod +x /etc/init.d/brcm4330-patch"
		chroot $DEST/output/sdcard /bin/bash -c "update-rc.d brcm4330-patch defaults>> /dev/null"
		
		cp $SRC/lib/scripts/mxobs $DEST/output/sdcard/etc/apt/preferences.d/mxobs
		mkdir -p $DEST/output/sdcard/etc/X11/
				cp $SRC/lib/config/xorg.conf.cubox $DEST/output/sdcard/etc/X11/xorg.conf.bak
		
		case $RELEASE in
		wheezy)
			echo "deb http://ftp.debian.org/debian/ wheezy-backports main contrib non-free" >> $DEST/output/sdcard/etc/apt/sources.list
			echo "deb-src http://ftp.debian.org/debian/ wheezy-backports main contrib non-free" >> $DEST/output/sdcard/etc/apt/sources.list
			echo "deb http://repo.jm0.eu/BSP:/Cubox-i/Debian_Wheezy/ ./" >> $DEST/output/sdcard/etc/apt/sources.list
			echo "deb-src http://repo.jm0.eu/BSP:/Cubox-i/Debian_Wheezy/ ./" >> $DEST/output/sdcard/etc/apt/sources.list
			chroot $DEST/output/sdcard /bin/bash -c "wget -qO - http://repo.jm0.eu/BSP:/Cubox-i/Debian_Wheezy/Release.key | apt-key add -"
			chroot $DEST/output/sdcard /bin/bash -c "apt-get update"		
			chroot $DEST/output/sdcard /bin/bash -c "apt-get install -y -qq irqbalance-imx"
		;;
		jessie)
			echo "deb http://repo.r00t.website/BSP:/Cubox-i/Debian_Jessie/ ./" >> $DEST/output/sdcard/etc/apt/sources.list
			chroot $DEST/output/sdcard /bin/bash -c "wget -qO - http://repo.r00t.website/BSP:/Cubox-i/Debian_Jessie/Release.key | apt-key add -"
			chroot $DEST/output/sdcard /bin/bash -c "apt-get update"		
			chroot $DEST/output/sdcard /bin/bash -c "apt-get install -y -qq irqbalance-imx"
		;;
		trusty)
			#echo "deb http://repo.r00t.website/BSP:/Cubox-i/Ubuntu_Trusty_Tahr/ ./" >> $DEST/output/sdcard/etc/apt/sources.list
			#chroot $DEST/output/sdcard /bin/bash -c "wget -qO - http://repo.r00t.website/BSP:/Cubox-i/Ubuntu_Trusty_Tahr/Release.key | apt-key add -"
			echo "" # currently not working
		;;
		esac				
	fi

# create board DEB file
cd $DEST/output/rootfs/
dpkg -b $CHOOSEN_ROOTFS >/dev/null 2>&1
rm -rf $CHOOSEN_ROOTFS
# install custom root package 
cp $CHOOSEN_ROOTFS.deb /tmp/kernel
chroot $DEST/output/sdcard /bin/bash -c "dpkg -i /tmp/$CHOOSEN_ROOTFS.deb >/dev/null 2>&1"
# enable first run script
chroot $DEST/output/sdcard /bin/bash -c "update-rc.d firstrun defaults >/dev/null 2>&1"
}


install_kernel (){
#--------------------------------------------------------------------------------------------------------------------------------
# Install kernel to prepared root file-system
#--------------------------------------------------------------------------------------------------------------------------------
echo -e "[\e[0;32m ok \x1B[0m] Install kernel"

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
chroot $DEST/output/sdcard /bin/bash -c "dpkg -i /tmp/*u-boot*.deb >/dev/null 2>&1"
chroot $DEST/output/sdcard /bin/bash -c "dpkg -i /tmp/*image*.deb >/dev/null 2>&1"
if ls $DEST/output/sdcard/tmp/*dtb* 1> /dev/null 2>&1; then
	chroot $DEST/output/sdcard /bin/bash -c "dpkg -i /tmp/*dtb*.deb >/dev/null 2>&1"
fi
# name of archive is also kernel name
CHOOSEN_KERNEL="${CHOOSEN_KERNEL//-$BRANCH.tar/}"

# recompile headers scripts or use cache if exists 
chroot $DEST/output/sdcard /bin/bash -c "dpkg -i /tmp/*headers*.deb >/dev/null 2>&1"
cd $DEST/output/sdcard/usr/src/linux-headers-$CHOOSEN_KERNEL

if [ ! -f $DEST/output/rootfs/$CHOOSEN_KERNEL-""$REVISION""-headers-make-cache.tgz ]; then
	echo -e "[\e[0;32m ok \x1B[0m] Compile kernel headers scripts"
	# patch scripts
	patch -p1 < $SRC/lib/patch/headers-debian-byteshift.patch
	chroot $DEST/output/sdcard /bin/bash -c "cd /usr/src/linux-headers-$CHOOSEN_KERNEL && make headers_check; make headers_install ; make scripts"
	tar czpf $DEST/output/rootfs/$CHOOSEN_KERNEL-""$REVISION""-headers-make-cache.tgz .
else
	tar xzpf $DEST/output/rootfs/$CHOOSEN_KERNEL-""$REVISION""-headers-make-cache.tgz
fi


# remove .old on new image
rm -rf $DEST/output/sdcard/boot/dtb.old
if [[ $BOARD == "udoo" ]] ; then
	cp $SRC/lib/config/boot-udoo-next.cmd $DEST/output/sdcard/boot/boot.cmd
elif [[ $BOARD == "udoo-neo" ]]; then
	cp $SRC/lib/config/boot-udoo-neo.cmd $DEST/output/sdcard/boot/boot.cmd
	#chroot $DEST/output/sdcard /bin/bash -c "ln -s /boot/boot.scr /boot.scr"	
elif [[ $BOARD == cubox-i* ]]; then
	cp $SRC/lib/config/boot-cubox.cmd $DEST/output/sdcard/boot/boot.cmd
else
	cp $SRC/lib/config/boot.cmd $DEST/output/sdcard/boot/boot.cmd
	# let's prepare for old kernel too
	chroot $DEST/output/sdcard /bin/bash -c "ln -s /boot/bin/$BOARD.bin /boot/script.bin"
fi
# convert to uboot compatible script
mkimage -C none -A arm -T script -d $DEST/output/sdcard/boot/boot.cmd $DEST/output/sdcard/boot/boot.scr >> /dev/null
		
# make symlink to kernel and uImage
#mkimage -A arm -O linux -T kernel -C none -a "0x40008000" -e "0x10008000" -n "Linux kernel" -d $DEST/output/sdcard/boot/vmlinuz-$CHOOSEN_KERNEL $DEST/output/sdcard/boot/uImage
#chroot $DEST/output/sdcard /bin/bash -c "ln -s /boot/vmlinuz-$CHOOSEN_KERNEL /boot/zImage"

# copy boot splash image
cp $SRC/lib/bin/armbian.bmp $DEST/output/sdcard/boot/boot.bmp
	
# add linux firmwares to output image
unzip -q $SRC/lib/bin/linux-firmware.zip -d $DEST/output/sdcard/lib/firmware
}


install_desktop (){
#--------------------------------------------------------------------------------------------------------------------------------
# Install desktop with HW acceleration
#--------------------------------------------------------------------------------------------------------------------------------
echo -e "[\e[0;32m ok \x1B[0m] Install desktop"
#chroot $DEST/output/sdcard /bin/bash -c "debconf-apt-progress -- apt-get -y install xorg lightdm xfce4 xfce4-goodies tango-icon-theme gnome-icon-theme pulseaudio gstreamer0.10-pulseaudio wicd"
# pwd expiration causes problems
chroot $DEST/output/sdcard /bin/bash -c "chage -d 10 root"
chroot $DEST/output/sdcard /bin/bash -c "debconf-apt-progress -- apt-get -y install xserver-xorg xserver-xorg-core xfonts-base xinit slim x11-xserver-utils mate-core mozo pluma mate-themes gnome-icon-theme"
chroot $DEST/output/sdcard /bin/bash -c "chage -d 0 root"
 
# configure slim
sed "s/current_theme\(.*\)/current_theme$(printf '\t')default/g" -i $DEST/output/sdcard/etc/slim.conf 
cp $SRC/lib/bin/slim-background.jpg $DEST/output/sdcard/usr/share/slim/themes/default/background.jpg
cp $SRC/lib/bin/slim-panel.png $DEST/output/sdcard/usr/share/slim/themes/default/panel.png

# skuapj
# chroot $DEST/output/sdcard /bin/bash -c "apt-get -y install gnome-core gnome-themes gnome-system-tools software-center xorg gdm3"


if [[ $LINUXCONFIG == *sunxi* && $RELEASE == "wheezy" ]]; then
 chroot $DEST/output/sdcard /bin/bash -c "apt-get -y install xorg-dev xutils-dev x11proto-dri2-dev xutils-dev libdrm-dev"
 # quemu bug walkaround
 git clone https://github.com/ssvb/xf86-video-fbturbo.git $DEST/output/sdcard/tmp/xf86-video-fbturbo
 chroot $DEST/output/sdcard /bin/bash -c "cd /tmp/xf86-video-fbturbo && autoreconf -vi"
 chroot $DEST/output/sdcard /bin/bash -c "cd /tmp/xf86-video-fbturbo && ./configure --prefix=/usr"
 chroot $DEST/output/sdcard /bin/bash -c "cd /tmp/xf86-video-fbturbo && make && make install && cp xorg.conf /etc/X11/xorg.conf"
 # enable root login
 sed -e "s/auth$(printf '\t')required/#auth$(printf '\t')required/g" -i /etc/pam.d/gdm3
 # clean deb cache
 chroot $DEST/output/sdcard /bin/bash -c "apt-get -y clean"	
fi
}
