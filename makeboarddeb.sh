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

create_board_package (){
#---------------------------------------------------------------------------------------------------------------------------------
# create .deb package for the rest
#---------------------------------------------------------------------------------------------------------------------------------

	display_alert "Creating board support package." "$BOARD" "info"

	if [[ $BRANCH == "next" ]]; then 
		ROOT_BRACH="-next"; 
	else 
		ROOT_BRACH=""; 
	fi  
	
	# construct a package name
	CHOOSEN_ROOTFS=linux-"$RELEASE"-root"$ROOT_BRACH"-"$BOARD"_"$REVISION"_armhf
	
	local destination=$DEST/debs/$RELEASE/$CHOOSEN_ROOTFS
	local controlfile=$destination/DEBIAN/control
	
	mkdir -p $destination/DEBIAN	
	
	echo "Package: linux-$RELEASE-root$ROOT_BRACH-$BOARD" > $controlfile	
	echo "Version: $REVISION" >> $controlfile
	echo "Architecture: armhf" >> $controlfile
	echo "Maintainer: $MAINTAINER <$MAINTAINERMAIL>" >> $controlfile
	echo "Installed-Size: 1" >> $controlfile
	echo "Section: kernel" >> $controlfile
	echo "Priority: optional" >> $controlfile
	echo "Description: Root file system tweaks for $BOARD" >> $controlfile

	# set up post install script
	echo "#!/bin/bash" > $destination/DEBIAN/postinst	
	chmod 755 $destination/DEBIAN/postinst

	# scripts for autoresize at first boot
	mkdir -p $destination/etc/init.d
	mkdir -p $destination/etc/default

	install -m 755 $SRC/lib/scripts/resize2fs $destination/etc/init.d
	install -m 755 $SRC/lib/scripts/firstrun  $destination/etc/init.d

	# install hardware info script
	install -m 755 $SRC/lib/scripts/armhwinfo $destination/etc/init.d 
	echo "set -e" >> $destination/DEBIAN/postinst
	echo "update-rc.d armhwinfo defaults >/dev/null 2>&1" >> $destination/DEBIAN/postinst
	echo "update-rc.d -f motd remove >/dev/null 2>&1" >> $destination/DEBIAN/postinst
	echo "[[ -f /root/.nand1-allwinner.tgz ]] && rm /root/.nand1-allwinner.tgz" >> $destination/DEBIAN/postinst
	echo "[[ -f /root/nand-sata-install ]] && rm /root/nand-sata-install" >> $destination/DEBIAN/postinst
	echo "ln -sf /var/run/motd /etc/motd" >> $destination/DEBIAN/postinst	
	echo "[[ -f /etc/bash.bashrc.custom ]] && rm /etc/bash.bashrc.custom" >> $destination/DEBIAN/postinst
	echo "exit 0" >> $destination/DEBIAN/postinst

	# temper binary for USB temp meter
	mkdir -p $destination/usr/local/bin
	tar xfz $SRC/lib/bin/temper.tgz -C $destination/usr/local/bin

	# replace hostapd from latest self compiled & patched
	mkdir -p $destination/usr/sbin/
	tar xfz $SRC/lib/bin/hostapd25-rt.tgz -C $destination/usr/sbin/
	tar xfz $SRC/lib/bin/hostapd25.tgz -C $destination/usr/sbin/

	# module evbug is loaded automagically at boot time but we don't want that
	mkdir -p $destination/etc/modprobe.d/
	echo "blacklist evbug" > $destination/etc/modprobe.d/ev-debug-blacklist.conf

	# script to install to SATA
	cp -R $SRC/lib/scripts/nand-sata-install/usr $destination/
	chmod +x $destination/usr/lib/nand-sata-install/nand-sata-install.sh
	ln -s ../lib/nand-sata-install/nand-sata-install.sh $destination/usr/sbin/nand-sata-install
	
	# install custom motd with reboot and upgrade checking
	mkdir -p $destination/root $destination/tmp $destination/etc/update-motd.d/ $destination/etc/profile.d
	install -m 755 $SRC/lib/scripts/update-motd.d/* $destination/etc/update-motd.d/	
	install -m 755 $SRC/lib/scripts/check_first_login_reboot.sh 	$destination/etc/profile.d
	install -m 755 $SRC/lib/scripts/check_first_login.sh 			$destination/etc/profile.d	
	cd $destination/
	ln -s ../var/run/motd etc/motd
	touch $destination/tmp/.reboot_required

	if [[ $LINUXCONFIG == *sun* ]] ; then

		# add sunxi tools	
		cp $SOURCES/$MISC1_DIR/meminfo $destination/usr/local/bin/meminfo
		cp $SOURCES/$MISC1_DIR/sunxi-nand-part $destination/usr/local/bin/nand-part
		cp $SOURCES/$MISC1_DIR/sunxi-fexc $destination/usr/local/bin/sunxi-fexc
		ln -s $destination/usr/sbin/sunxi-fexc $destination/usr/sbin/fex2bin
		ln -s $destination/usr/sbin/sunxi-fexc $destination/usr/sbin/bin2fex
		if [ "$BRANCH" != "next" ]; then
			# add soc temperature app
			arm-linux-gnueabihf-gcc $SRC/lib/scripts/sunxi-temp/sunxi_tp_temp.c -o $destination/usr/local/bin/sunxi_tp_temp
		fi
	
		# lamobo R1 router switch config
		tar xfz $SRC/lib/bin/swconfig.tgz -C $destination/usr/local/bin
	
		# convert and add fex files
		unset IFS
		mkdir -p $destination/boot/bin
		for i in $(ls -w1 $SRC/lib/config/*.fex | xargs -n1 basename); do
			fex2bin $SRC/lib/config/${i%*.fex}.fex $destination/boot/bin/${i%*.fex}.bin; 
		done
	
		# bluetooth device enabler - for cubietruck
		install -m 755	$SRC/lib/bin/brcm_patchram_plus		$destination/usr/local/bin
		install			$SRC/lib/scripts/brcm40183 			$destination/etc/default
		install -m 755  $SRC/lib/scripts/brcm40183-patch    $destination/etc/init.d
		
	fi

	# add some summary to the image
	fingerprint_image "$destination/etc/armbian.txt"
	
	# create board DEB file
	cd $DEST/debs/$RELEASE/
	display_alert "Building deb package." "$CHOOSEN_ROOTFS"".deb" "info"
	dpkg -b $CHOOSEN_ROOTFS >/dev/null 2>&1
	
	# clean up
	rm -rf $CHOOSEN_ROOTFS	
	rm -f ../.reboot_required
}