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

create_board_package (){
#---------------------------------------------------------------------------------------------------------------------------------
# create .deb package for the rest
#---------------------------------------------------------------------------------------------------------------------------------
display_alert "Creating board support package." "$BOARD" "info"

if [[ $BRANCH == "next" ]] ; then ROOT_BRACH="-next"; else ROOT_BRACH=""; fi  

CHOOSEN_ROOTFS=linux-"$RELEASE"-root"$ROOT_BRACH"-"$BOARD"_"$REVISION"_armhf

mkdir -p $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/DEBIAN
cat <<END > $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/DEBIAN/control
Package: linux-$RELEASE-root$ROOT_BRACH-$BOARD
Version: $REVISION
Architecture: armhf
Maintainer: $MAINTAINER <$MAINTAINERMAIL>
Installed-Size: 1
Section: kernel
Priority: optional
Description: Root file system tweaks for $BOARD
END

# set up post install script
echo "#!/bin/bash" > $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/DEBIAN/postinst
chmod 755 $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/DEBIAN/postinst
# scripts for autoresize at first boot
mkdir -p $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/etc/init.d
mkdir -p $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/etc/default
install -m 755 $SRC/lib/scripts/resize2fs $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/etc/init.d
install -m 755 $SRC/lib/scripts/firstrun  $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/etc/init.d
# install custom bashrc and hardware dependent motd
install $SRC/lib/scripts/bashrc $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/etc/bash.bashrc.custom
install -m 755 $SRC/lib/scripts/armhwinfo $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/etc/init.d 
echo "set -e" >> $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/DEBIAN/postinst
echo "update-rc.d armhwinfo defaults >/dev/null 2>&1" >> $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/DEBIAN/postinst
echo "update-rc.d -f motd remove >/dev/null 2>&1" >> $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/DEBIAN/postinst
echo "[[ -f /root/.nand1-allwinner.tgz ]] && rm /root/.nand1-allwinner.tgz" >> $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/DEBIAN/postinst
echo "[[ -f /root/nand-sata-install ]] && rm /root/nand-sata-install" >> $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/DEBIAN/postinst
echo "exit 0" >> $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/DEBIAN/postinst

# temper binary for USB temp meter
mkdir -p $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/usr/local/bin
tar xfz $SRC/lib/bin/temper.tgz -C $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/usr/local/bin

# replace hostapd from latest self compiled & patched
mkdir -p $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/usr/sbin/
tar xfz $SRC/lib/bin/hostapd25-rt.tgz -C $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/usr/sbin/
tar xfz $SRC/lib/bin/hostapd25.tgz -C $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/usr/sbin/

# module evbug is loaded automagically at boot time but we don't want that
mkdir -p $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/etc/modprobe.d/
echo "blacklist evbug" > $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/etc/modprobe.d/ev-debug-blacklist.conf

# script to install to SATA
cp -R $SRC/lib/scripts/nand-sata-install/usr $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/
chmod +x $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/usr/lib/nand-sata-install/nand-sata-install.sh
ln -s ../lib/nand-sata-install/nand-sata-install.sh $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/usr/sbin/nand-sata-install


if [[ $LINUXCONFIG == *sun* ]] ; then

	# add sunxi tools
	# cp $SOURCES/sunxi-tools/fex2bin $SOURCES/sunxi-tools/bin2fex $SOURCES/sunxi-tools/nand-part $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/usr/local/bin
	tar xfz $SRC/lib/bin/sunxitools.tgz -C $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/usr/local/bin
	if [ "$BRANCH" != "next" ]; then
		# add soc temperature app
		arm-linux-gnueabihf-gcc $SRC/lib/scripts/sunxi-temp/sunxi_tp_temp.c -o $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/usr/local/bin/sunxi_tp_temp
	fi
	
	# lamobo R1 router switch config
	tar xfz $SRC/lib/bin/swconfig.tgz -C $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/usr/local/bin
	
	# convert and add fex files
	unset IFS
	mkdir -p $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/boot/bin
	for i in $(ls -w1 $SRC/lib/config/*.fex | xargs -n1 basename); 
		do fex2bin $SRC/lib/config/${i%*.fex}.fex $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/boot/bin/${i%*.fex}.bin; 
	done
	
	# bluetooth device enabler - for cubietruck
	install -m 755	$SRC/lib/bin/brcm_patchram_plus		$DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/usr/local/bin
	install			$SRC/lib/scripts/brcm40183 			$DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/etc/default
	install -m 755  $SRC/lib/scripts/brcm40183-patch    $DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/etc/init.d
fi






# add some summary to the image
fingerprint_image "$DEST/debs/$RELEASE/$CHOOSEN_ROOTFS/etc/armbian.txt"

# create board DEB file
cd $DEST/debs/$RELEASE/
dpkg -b $CHOOSEN_ROOTFS >/dev/null 2>&1
rm -rf $CHOOSEN_ROOTFS

}