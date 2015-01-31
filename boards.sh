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
clear
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
		# enable serial console (Debian/sysvinit way)
		echo T0:2345:respawn:/sbin/getty -L ttyS0 115200 vt100 >> $DEST/output/sdcard/etc/inittab		
		if [[ $BRANCH == *next* ]] ; then
				# remove some unsupported stuff from mainline
				chroot $DEST/output/sdcard /bin/bash -c "apt-get -y -qq remove cpufrequtils lirc alsa-utils alsa-base && apt-get -y -qq autoremove"
			else
				# sunxi tools
				cp $DEST/sunxi-tools/fex2bin $DEST/sunxi-tools/bin2fex $DEST/sunxi-tools/nand-part $DEST/output/sdcard/usr/bin/				
				# remove serial console from hummingboard / cubox
				rm -f $DEST/output/sdcard/etc/init/ttymxc0.conf
				# NAND & SATA install for all except
				# cp $SRC/lib/scripts/nand-sata-install.sh $DEST/output/sdcard/root
				if [[ $BOARD != "bananapi" ]] ; then
					cp $SRC/lib/bin/nand1-allwinner.tgz $DEST/output/sdcard/root
				fi # NAND				
		
		if [[ $BOARD == "cubietruck" || $BOARD == "cubieboard2"  || $BOARD == "bananapi" ]] ; then
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
			cp $SRC/lib/bin/hostapd.realtek $DEST/output/sdcard/usr/sbin/hostapd
			chroot $DEST/output/sdcard /bin/bash -c "chmod +x /usr/sbin/hostapd"
			cp $SRC/lib/config/hostapd.realtek.conf $DEST/output/sdcard/etc/hostapd.conf
		fi # orangepi
		fi #NEXT
fi # SUNXI




if [[ $BOARD == cubox-i* || $BOARD == udoo* ]] ; then
		cp $SRC/lib/config/uEnv.cubox-i $DEST/output/sdcard/boot/uEnv.txt
		cp $DEST/$LINUXSOURCE/arch/arm/boot/dts/*.dtb $DEST/output/sdcard/boot
		chroot $DEST/output/sdcard /bin/bash -c "chmod 755 /boot/uEnv.txt"
		# enable serial console (Debian/sysvinit way)
		rm $DEST/output/sdcard/etc/init/ttyS0.conf
		if [[ "$RELEASE" == "trusty" ]]; then
		#chroot $DEST/output/sdcard /bin/bash -c "systemctl enable serial-getty@ttymxc0.service"
		#chroot $DEST/output/sdcard /bin/bash -c "systemctl start serial-getty@ttymxc0.service"
		echo "Trusty"
		else
		echo T0:2345:respawn:/sbin/getty -L ttymxc0 115200 vt100 >> $DEST/output/sdcard/etc/inittab
		fi
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
		chroot $DEST/output/sdcard /bin/bash -c "wget -qO - http://repo.maltegrosse.de/debian/wheezy/bsp_cuboxi/Release.key | apt-key add -"
		echo "deb http://repo.maltegrosse.de/debian/wheezy/bsp_cuboxi/ ./" >> $DEST/output/sdcard/etc/apt/sources.list
		echo "deb-src http://repo.maltegrosse.de/debian/wheezy/bsp_cuboxi/ ./" >> $DEST/output/sdcard/etc/apt/sources.list
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
for word in $MODULES; do echo $word >> $DEST/output/sdcard/etc/modules; done

# script to install to SATA
cp $SRC/lib/scripts/nand-sata-install.sh $DEST/output/sdcard/root

# copy and create symlink to default interfaces configuration
cp $SRC/lib/config/interfaces.* $DEST/output/sdcard/etc/network/
ln -sf interfaces.default $DEST/output/sdcard/etc/network/interfaces

# install kernel
rm -rf /tmp/kernel && mkdir -p /tmp/kernel && cd /tmp/kernel
tar -xPf $DEST"/output/kernel/"$CHOOSEN_KERNEL
mount --bind /tmp/kernel/ $DEST/output/sdcard/tmp
chroot $DEST/output/sdcard /bin/bash -c "dpkg -i /tmp/*.deb"

# name of archive is also kernel name
CHOOSEN_KERNEL="${CHOOSEN_KERNEL//-$BRANCH.tar/}"

echo "------ Compile headers scripts"
# recompile headers scripts
chroot $DEST/output/sdcard /bin/bash -c "cd /usr/src/linux-headers-$CHOOSEN_KERNEL && make scripts"

# recreate boot.scr if using kernel for different board. Mainline only
if [[ $BRANCH == *next* ]];then
		# remove .old on new image
		rm -rf $DEST/output/sdcard/boot/dtb/$CHOOSEN_KERNEL.old
		# copy boot script and change it acordingly
		cp $SRC/lib/config/boot-next.cmd $DEST/output/sdcard/boot/boot-next.cmd
		sed -e "s/zImage/vmlinuz-$CHOOSEN_KERNEL/g" -i $DEST/output/sdcard/boot/boot-next.cmd
		sed -e "s/dtb/dtb\/$CHOOSEN_KERNEL/g" -i $DEST/output/sdcard/boot/boot-next.cmd
		# compile boot script
		mkimage -C none -A arm -T script -d $DEST/output/sdcard/boot/boot-next.cmd $DEST/output/sdcard/boot/boot.scr >> /dev/null
	elif [[ $LINUXCONFIG == *sunxi* ]]; then
		fex2bin $SRC/lib/config/$BOARD.fex $DEST/output/sdcard/boot/$BOARD.bin
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