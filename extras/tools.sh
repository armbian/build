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


compile_tools ()
{
	
	sync
	echo "Building sunxi-tools" > $DEST/debug/sunxi-tools-build.log 2>&1
	display_alert "Building deb" "sunxi-tools" "info"
	
		local tmpdir1="sdcard/tmp/sunxi-tools"
		display_alert "... downloading sources" "sunxi-tools" "info"		
		git clone https://github.com/linux-sunxi/sunxi-tools $CACHEDIR/$tmpdir1 >> $DEST/debug/sunxi-tools-build.log 2>&1
		
		local tmpdir2="sdcard/tmp/temper"
		display_alert "... downloading sources" "temper" "info"		
		git clone -q https://github.com/padelt/pcsensor-temper $CACHEDIR/$tmpdir2 >> $DEST/debug/temper-build.log 2>&1
		
		local tmpdir3="sdcard/tmp/brcm"
		display_alert "... downloading sources" "BT utils" "info"		
		git clone -q https://github.com/phelum/CT_Bluetooth $CACHEDIR/$tmpdir3 >> $DEST/debug/brcm-build.log 2>&1	
		rm -f $CACHEDIR/$tmpdir3/brcm_patchram_plus $CACHEDIR/$tmpdir3/brcm_bt_reset $CACHEDIR/$tmpdir3/*.o
	
	pack_to_deb ()
	{
		cd $CACHEDIR/sdcard/tmp
		mkdir -p armbian-tools${TARGET}"_"${REVISION}_${ARCH}/DEBIAN armbian-tools${TARGET}"_"${REVISION}_${ARCH}/usr/bin armbian-tools${TARGET}"_"${REVISION}_${ARCH}/lib/udev/rules.d

		# set up control file
cat <<END > armbian-tools${TARGET}_${REVISION}_${ARCH}/DEBIAN/control
Package: armbian-tools$TARGET
Version: $REVISION
Architecture: $ARCH
Maintainer: $MAINTAINER <$MAINTAINERMAIL>
Installed-Size: 1
Depends: libc6 (>= 2.10), libusb-1.0-0 (>= 2:1.0.8) 
Section: utils
Priority: optional
Description: Armbian tools, sunxi, temper
END
#
		echo 'SUBSYSTEMS=="usb", ATTR{idVendor}=="1f3a", ATTR{idProduct}=="efe8", GROUP="sunxi-fel"' > armbian-tools${TARGET}_${REVISION}_${ARCH}/lib/udev/rules.d/60-sunxi-tools.rules
		cp "$CACHEDIR/$tmpdir1/sunxi-bootinfo" 		armbian-tools${TARGET}_${REVISION}_${ARCH}/usr/bin
		cp "$CACHEDIR/$tmpdir1/sunxi-fel" 			armbian-tools${TARGET}_${REVISION}_${ARCH}/usr/bin
		cp "$CACHEDIR/$tmpdir1/sunxi-fexc"  			armbian-tools${TARGET}_${REVISION}_${ARCH}/usr/bin		
		ln -s sunxi-fexc armbian-tools${TARGET}_${REVISION}_${ARCH}/usr/bin/fex2bin
		ln -s sunxi-fexc armbian-tools${TARGET}_${REVISION}_${ARCH}/usr/bin/bin2fex
		cp "$CACHEDIR/$tmpdir1/sunxi-nand-part" 		armbian-tools${TARGET}_${REVISION}_${ARCH}/usr/bin
		cp "$CACHEDIR/$tmpdir1/sunxi-pio" 			armbian-tools${TARGET}_${REVISION}_${ARCH}/usr/bin
		# temper
		cp "$CACHEDIR/$tmpdir2/src/pcsensor" 			armbian-tools${TARGET}_${REVISION}_${ARCH}/usr/bin/temper
		# brcm
		cp "$CACHEDIR/$tmpdir3/brcm_bt_reset" 			armbian-tools${TARGET}_${REVISION}_${ARCH}/usr/bin
		cp "$CACHEDIR/$tmpdir3/brcm_patchram_plus" 			armbian-tools${TARGET}_${REVISION}_${ARCH}/usr/bin
		
		cd armbian-tools${TARGET}_${REVISION}_${ARCH}
		find . -type f ! -regex '.*.hg.*' ! -regex '.*?debian-binary.*' ! -regex '.*?DEBIAN.*' -printf '%P ' | xargs md5sum > DEBIAN/md5sums
		cd ..
		dpkg -b armbian-tools${TARGET}_${REVISION}_${ARCH} >/dev/null 2>&1		
		rm -rf armbian-tools${TARGET}_${REVISION}_${ARCH}
	}
	
	
	compiling ()
	{	
		display_alert "... compiling" "sunxitools" "info"	
		cd $CACHEDIR/$tmpdir1
		git checkout -f -q ce9cf33606492076b81e1157ba9fc54b56379335 >> $DEST/debug/tools-build.log 2>&1
		chroot $CACHEDIR/sdcard /bin/bash -c "cd /tmp/sunxi-tools; make clean" >> $DEST/debug/tools-build.log 2>&1
		chroot $CACHEDIR/sdcard /bin/bash -c "cd /tmp/sunxi-tools; make $CTHREADS" >> $DEST/debug/tools-build.log 2>&1			
		if [ $? -ne 0 ] || [ ! -f $CACHEDIR/$tmpdir1/sunxi-fexc ]; then
			display_alert "Not built" "tools" "err"
			exit 1
		fi
		display_alert "... compiling" "temper" "info"	
		chroot $CACHEDIR/sdcard /bin/bash -c "cd /tmp/temper/src; make clean" >> $DEST/debug/tools-build.log 2>&1
		chroot $CACHEDIR/sdcard /bin/bash -c "cd /tmp/temper/src; make $CTHREADS" >> $DEST/debug/tools-build.log 2>&1			
		if [ $? -ne 0 ] || [ ! -f $CACHEDIR/$tmpdir2/src/pcsensor ]; then
			display_alert "Not built" "tools" "err"
			exit 1
		fi
		display_alert "... compiling" "bluetooth utils" "info"			
		chroot $CACHEDIR/sdcard /bin/bash -c "cd /tmp/brcm; make $CTHREADS" >> $DEST/debug/tools-build.log 2>&1			
		if [ $? -ne 0 ] || [ ! -f $CACHEDIR/$tmpdir3/brcm_bt_reset ]; then
			display_alert "Not built" "tools" "err"
			exit 1
		fi
	}
	
	compiling
	pack_to_deb

	display_alert "Installing" "armbian-tools${TARGET}_${REVISION}_${ARCH}.deb" "info"
	chroot $CACHEDIR/sdcard /bin/bash -c "dpkg -i /tmp/armbian-tools${TARGET}_${REVISION}_${ARCH}.deb" >> $DEST/debug/tools-build.log 2>&1 
	mv $CACHEDIR/sdcard/tmp/armbian-tools${TARGET}_${REVISION}_${ARCH}.deb $DEST/debs
}


if [[ -f "$DEST/debs/armbian-tools${TARGET}_${REVISION}_${ARCH}.deb" ]]; then
	# install
	echo "Installing tools" > $DEST/debug/tools-build.log 2>&1
	display_alert "Installing" "armbian-tools${TARGET}_${REVISION}_${ARCH}.deb" "info"
	cp $DEST/debs/armbian-tools${TARGET}_${REVISION}_${ARCH}.deb $CACHEDIR/sdcard/tmp
	chroot $CACHEDIR/sdcard /bin/bash -c "dpkg -i /tmp/armbian-tools${TARGET}_${REVISION}_${ARCH}.deb" >> $DEST/debug/tools-build.log 2>&1 
else
	# compile
	compile_tools
fi