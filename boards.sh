#!/bin/bash

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
# set fstab
#UUID=$(cat /proc/sys/kernel/random/uuid)
#tune2fs -U $UUID $LOOP
#echo "UUID=$UUID  /           ext4    defaults,noatime,nodiratime,data=writeback,commit=600,errors=remount-ro        0       0" > $DEST/output/sdcard/etc/fstab
echo "/dev/mmcblk0p1  /           ext4    defaults,noatime,nodiratime,data=writeback,commit=600,errors=remount-ro        0       0" > $DEST/output/sdcard/etc/fstab

# mount proc, sys and dev
mount -t proc chproc $DEST/output/sdcard/proc
mount -t sysfs chsys $DEST/output/sdcard/sys
mount -t devtmpfs chdev $DEST/output/sdcard/dev || mount --bind /dev $DEST/output/sdcard/dev
mount -t devpts chpts $DEST/output/sdcard/dev/pts
}


install_board_specific (){
#--------------------------------------------------------------------------------------------------------------------------------
# Install board specific applications  					                    
#--------------------------------------------------------------------------------------------------------------------------------
echo "------ Install board specific applications"

if [[ $BOARD == "lime" || $BOARD == "lime2" || $BOARD == "micro" ]] ; then
		chroot $DEST/output/sdcard /bin/bash -c "apt-get -y -qq remove lirc alsa-utils alsa-base && apt-get -y -qq autoremove"
fi

# for allwinner boards
if [[ $LINUXCONFIG == *sunxi* ]] ; then
		
		# add irq to second core - rc.local
		head -n -1 $DEST/output/sdcard/etc/rc.local > /tmp/out
		echo 'echo 2 > /proc/irq/$(cat /proc/interrupts | grep eth0 | cut -f 1 -d ":" | tr -d " ")/smp_affinity' >> /tmp/out
		echo 'exit 0' >> /tmp/out
		mv /tmp/out $DEST/output/sdcard/etc/rc.local
		chroot $DEST/output/sdcard /bin/bash -c "chmod +x /etc/rc.local"		
		
		# add sunxi tools
		cp $DEST/sunxi-tools/fex2bin $DEST/sunxi-tools/bin2fex $DEST/sunxi-tools/nand-part $DEST/output/sdcard/usr/bin/				
		
		# add NAND boot content
		if [[ $BOARD != "bananapi" ]] ; then
			cp $SRC/lib/bin/nand1-allwinner.tgz $DEST/output/sdcard/root
		fi
		
		# remove some unsupported stuff from mainline
		if [[ $BRANCH == *next* ]] ; then				
				chroot $DEST/output/sdcard /bin/bash -c "apt-get -y -qq remove lirc alsa-utils alsa-base && apt-get -y -qq autoremove"
		fi
		
		if [[ $BOARD == "cubietruck" || $BOARD == "cubieboard2"  || $BOARD == bananapi* || $BOARD == "orangepi" ]] ; then
			# Bananpi router switch config
			tar xvfz $SRC/lib/bin/swconfig.tgz -C $DEST/output/sdcard/usr/sbin/
			# bluetooth device enabler - for cubietruck
			cp $SRC/lib/bin/brcm_patchram_plus $DEST/output/sdcard/usr/local/bin/brcm_patchram_plus
			chroot $DEST/output/sdcard /bin/bash -c "chmod +x /usr/local/bin/brcm_patchram_plus"
			cp $SRC/lib/scripts/brcm40183 $DEST/output/sdcard/etc/default
			cp $SRC/lib/scripts/brcm40183-patch $DEST/output/sdcard/etc/init.d
			chroot $DEST/output/sdcard /bin/bash -c "chmod +x /etc/init.d/brcm40183-patch"
			# default lirc configuration
			sed -i '1i sed -i \x27s/DEVICE="\\/dev\\/input.*/DEVICE="\\/dev\\/input\\/\x27$str\x27"/g\x27 /etc/lirc/hardware.conf' $DEST/output/sdcard/etc/lirc/hardware.conf
			sed -i '1i str=$(cat /proc/bus/input/devices | grep "H: Handlers=sysrq rfkill kbd event" | awk \x27{print $(NF)}\x27)' $DEST/output/sdcard/etc/lirc/hardware.conf
			sed -i '1i # Cubietruck automatic lirc device detection by Igor Pecovnik' $DEST/output/sdcard/etc/lirc/hardware.conf
			sed -e 's/DEVICE=""/DEVICE="\/dev\/input\/event1"/g' -i $DEST/output/sdcard/etc/lirc/hardware.conf
			sed -e 's/DRIVER="UNCONFIGURED"/DRIVER="devinput"/g' -i $DEST/output/sdcard/etc/lirc/hardware.conf
			cp $SRC/lib/config/lirc.conf.cubietruck $DEST/output/sdcard/etc/lirc/lircd.conf
		fi # cubieboards
		if [[ $BOARD == "orangepi" ]] ; then
			# realtek have special hostapd
		    tar xvfz $SRC/lib/bin/hostapd24-rtl871xdrv.tgz -C $DEST/output/sdcard/usr/sbin/			
			cp $SRC/lib/config/hostapd.realtek.conf $DEST/output/sdcard/etc/hostapd.conf
		fi # orangepi		
fi # SUNXI

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
		
		#cp $SRC/lib/config/uEnv.cubox-i $DEST/output/sdcard/boot/uEnv.txt
		#cp $DEST/$LINUXSOURCE/arch/arm/boot/dts/*.dtb $DEST/output/sdcard/boot
		#chroot $DEST/output/sdcard /bin/bash -c "chmod 755 /boot/uEnv.txt"

		
		
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
echo "------ done."
}


install_kernel (){
#--------------------------------------------------------------------------------------------------------------------------------
# Install kernel to prepared root file-system  								                    
#--------------------------------------------------------------------------------------------------------------------------------
echo "------ Install kernel"

# configure MIN / MAX Speed for cpufrequtils
sed -e "s/MIN_SPEED=\"0\"/MIN_SPEED=\"$CPUMIN\"/g" -i $DEST/output/sdcard/etc/init.d/cpufrequtils
sed -e "s/MAX_SPEED=\"0\"/MAX_SPEED=\"$CPUMAX\"/g" -i $DEST/output/sdcard/etc/init.d/cpufrequtils
sed -e 's/ondemand/interactive/g' -i $DEST/output/sdcard/etc/init.d/cpufrequtils

# alter hostap configuration
sed -i "s/BOARD/$BOARD/" $DEST/output/sdcard/etc/hostapd.conf

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
# script to install to SATA
cp $SRC/lib/scripts/nand-sata-install.sh $DEST/output/sdcard/root
chroot $DEST/output/sdcard /bin/bash -c "chmod +x /root/nand-sata-install.sh"

# copy and create symlink to default interfaces configuration
cp $SRC/lib/config/interfaces.* $DEST/output/sdcard/etc/network/
ln -sf interfaces.default $DEST/output/sdcard/etc/network/interfaces

# install kernel
rm -rf /tmp/kernel && mkdir -p /tmp/kernel && cd /tmp/kernel
tar -xPf $DEST"/output/kernel/"$CHOOSEN_KERNEL
mount --bind /tmp/kernel/ $DEST/output/sdcard/tmp
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
			cp $SRC/lib/config/boot-next.cmd $DEST/output/sdcard/boot/boot-next.cmd
		fi		
		#sed -e "s/zImage/vmlinuz-$CHOOSEN_KERNEL/g" -i $DEST/output/sdcard/boot/boot-next.cmd
		#chroot $DEST/output/sdcard /bin/bash -c "ln -s /boot/vmlinuz-$CHOOSEN_KERNEL /boot/zImage"
		#sed -e "s/dtb/dtb\/$CHOOSEN_KERNEL/g" -i $DEST/output/sdcard/boot/boot-next.cmd
		# compile boot script
		mkimage -C none -A arm -T script -d $DEST/output/sdcard/boot/boot-next.cmd $DEST/output/sdcard/boot/boot.scr >> /dev/null
	elif [[ $LINUXCONFIG == *sunxi* ]]; then
		fex2bin $SRC/lib/config/$BOARD.fex $DEST/output/sdcard/boot/$BOARD.bin
		if [[ $BOARD == "bananapi" ]] ; then
				fex2bin $SRC/lib/config/bananapipro.fex $DEST/output/sdcard/boot/bananapipro.bin
				fex2bin $SRC/lib/config/bananapir1.fex $DEST/output/sdcard/boot/bananapir1.bin
		fi # bananapi
		cp $SRC/lib/config/boot.cmd $DEST/output/sdcard/boot/boot.cmd
		sed -e "s/zImage/vmlinuz-$CHOOSEN_KERNEL/g" -i $DEST/output/sdcard/boot/boot.cmd
		sed -e "s/script.bin/$BOARD.bin/g" -i $DEST/output/sdcard/boot/boot.cmd
		# compile boot script
		mkimage -C none -A arm -T script -d $DEST/output/sdcard/boot/boot.cmd $DEST/output/sdcard/boot/boot.scr >> /dev/null
	else
		# make symlink to kernel and uImage
		mkimage -A arm -O linux -T kernel -C none -a "0x40008000" -e "0x10008000" -n "Linux kernel" -d $DEST/output/sdcard/boot/vmlinuz-$CHOOSEN_KERNEL $DEST/output/sdcard/boot/uImage
		chroot $DEST/output/sdcard /bin/bash -c "ln -s /boot/vmlinuz-$CHOOSEN_KERNEL /boot/zImage"
fi

# add linux firmwares to output image
unzip $SRC/lib/bin/linux-firmware.zip -d $DEST/output/sdcard/lib/firmware
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