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

	display_alert "Creating board support package" "$BOARD" "info"

	if [[ $BRANCH == next ]]; then
		ROOT_BRACH="-next";
	else
		ROOT_BRACH="";
	fi

	local destination=$DEST/debs/$RELEASE/${CHOSEN_ROOTFS}_${REVISION}_${ARCH}
	local controlfile=$destination/DEBIAN/control
	local configfilelist=$destination/DEBIAN/conffiles

	mkdir -p $destination/DEBIAN

	echo "Package: linux-$RELEASE-root$ROOT_BRACH-$BOARD" > $controlfile
	echo "Version: $REVISION" >> $controlfile
	echo "Architecture: $ARCH" >> $controlfile
	echo "Maintainer: $MAINTAINER <$MAINTAINERMAIL>" >> $controlfile
	echo "Installed-Size: 1" >> $controlfile
	echo "Section: kernel" >> $controlfile
	echo "Priority: optional" >> $controlfile
	echo "Recommends: fake-hwclock, initramfs-tools" >> $controlfile
	echo "Description: Root file system tweaks for $BOARD" >> $controlfile

	# set up pre install script
	echo "#!/bin/bash" > $destination/DEBIAN/preinst
	chmod 755 $destination/DEBIAN/preinst
	echo "[[ -d /boot/bin ]] && mv /boot/bin /boot/bin.old" >> $destination/DEBIAN/preinst
	echo "exit 0" >> $destination/DEBIAN/preinst

	# set up post install script
	echo "#!/bin/bash" > $destination/DEBIAN/postinst
	chmod 755 $destination/DEBIAN/postinst

	# won't recreate files if they were removed by user
	echo "/tmp/.reboot_required" > $configfilelist
	echo "/boot/.verbose" >> $configfilelist

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
	echo "[[ -f /etc/update-motd.d/00-header ]] && rm /etc/update-motd.d/00-header" >> $destination/DEBIAN/postinst
	echo "[[ -f /etc/update-motd.d/10-help-text ]] && rm /etc/update-motd.d/10-help-text" >> $destination/DEBIAN/postinst
	echo "if [[ -d /boot/bin && ! -f /boot/script.bin ]]; then ln -sf bin/$BOARD.bin /boot/script.bin >/dev/null 2>&1 || cp /boot/bin/$BOARD.bin /boot/script.bin; fi">> $destination/DEBIAN/postinst
	echo "exit 0" >> $destination/DEBIAN/postinst

	# temper binary for USB temp meter
	mkdir -p $destination/usr/local/bin
	tar xfz $SRC/lib/bin/temper.tgz -C $destination/usr/local/bin

	# add USB OTG port mode switcher
	install -m 755 $SRC/lib/scripts/sunxi-musb 			$destination/usr/local/bin

	# armbianmonitor (currently only to toggle boot verbosity and log upload)
	install -m 755 $SRC/lib/scripts/armbianmonitor/armbianmonitor $destination/usr/local/bin

	# module evbug is loaded automagically at boot time but we don't want that
	mkdir -p $destination/etc/modprobe.d/
	echo "blacklist evbug" > $destination/etc/modprobe.d/ev-debug-blacklist.conf

	# updating uInitrd image in update-initramfs trigger
	mkdir -p $destination/etc/initramfs/post-update.d/
	cat <<-EOF > $destination/etc/initramfs/post-update.d/99-uboot
	#!/bin/sh
	mkimage -A $ARCHITECTURE -O linux -T ramdisk -C gzip -n uInitrd -d \$2 /boot/uInitrd > /dev/null
	exit 0
	EOF
	chmod +x $destination/etc/initramfs/post-update.d/99-uboot

	# script to install to SATA
	mkdir -p $destination/usr/sbin/
	cp -R $SRC/lib/scripts/nand-sata-install/usr $destination/
	chmod +x $destination/usr/lib/nand-sata-install/nand-sata-install.sh
	ln -s ../lib/nand-sata-install/nand-sata-install.sh $destination/usr/sbin/nand-sata-install

	# install custom motd with reboot and upgrade checking
	mkdir -p $destination/root $destination/tmp $destination/etc/update-motd.d/ $destination/etc/profile.d
	install -m 755 $SRC/lib/scripts/update-motd.d/* $destination/etc/update-motd.d/
	install -m 755 $SRC/lib/scripts/check_first_login_reboot.sh 	$destination/etc/profile.d
	install -m 755 $SRC/lib/scripts/check_first_login.sh 			$destination/etc/profile.d

	# export arhitecture
	echo "#!/bin/bash" > $destination/etc/profile.d/arhitecture.sh
	if [[ $ARCH == *64* ]]; then
		echo "export ARCH=arm64" >> $destination/etc/profile.d/arhitecture.sh
	else
		echo "export ARCH=arm" >> $destination/etc/profile.d/arhitecture.sh
	fi
	chmod 755 $destination/etc/profile.d/arhitecture.sh

	cd $destination/
	ln -s ../var/run/motd etc/motd
	touch $destination/tmp/.reboot_required

	if [[ $LINUXCONFIG == *sun* ]] ; then
		if [[ $BRANCH != next ]]; then
			# add soc temperature app
			local codename=$(lsb_release -sc)
			if [[ -z $codename || "sid" == *"$codename"* ]]; then
				arm-linux-gnueabihf-gcc-5 $SRC/lib/scripts/sunxi-temp/sunxi_tp_temp.c -o $destination/usr/local/bin/sunxi_tp_temp
			else
				arm-linux-gnueabihf-gcc $SRC/lib/scripts/sunxi-temp/sunxi_tp_temp.c -o $destination/usr/local/bin/sunxi_tp_temp
			fi
		fi

		# lamobo R1 router switch config
		tar xfz $SRC/lib/bin/swconfig.tgz -C $destination/usr/local/bin

		# convert and add fex files
		mkdir -p $destination/boot/bin
		for i in $(ls -w1 $SRC/lib/config/fex/*.fex | xargs -n1 basename); do
			fex2bin $SRC/lib/config/fex/${i%*.fex}.fex $destination/boot/bin/${i%*.fex}.bin
		done
		# One H3 image for all Fast Ethernet equipped Orange Pi H3
		cp -p "$destination/boot/bin/orangepi2.bin" "$destination/boot/bin/orangepih3.bin"

		# bluetooth device enabler - for cubietruck
		install -m 755	$SRC/lib/bin/brcm_bt_reset			$destination/usr/local/bin
		install -m 755	$SRC/lib/bin/brcm_patchram_plus		$destination/usr/local/bin
		install			$SRC/lib/scripts/brcm40183 			$destination/etc/default
		install -m 755  $SRC/lib/scripts/brcm40183-patch    $destination/etc/init.d

	fi

	# enable verbose kernel messages on first boot
	mkdir -p $destination/boot
	touch $destination/boot/.verbose

	# add some summary to the image
	fingerprint_image "$destination/etc/armbian.txt"

	# create board DEB file
	cd $DEST/debs/$RELEASE/
	display_alert "Building package" "$CHOSEN_ROOTFS" "info"
	dpkg -b ${CHOSEN_ROOTFS}_${REVISION}_${ARCH} >/dev/null

	# clean up
	rm -rf ${CHOSEN_ROOTFS}_${REVISION}_${ARCH}
	rm -f ../.reboot_required
}
