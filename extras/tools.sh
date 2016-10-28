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

compile_tools()
{
	local tmpdir=$CACHEDIR/sdcard/root/tools

	display_alert "Building deb" "armbian-tools" "info"

	display_alert "... downloading sources" "temper" "info"
	git clone -q https://github.com/padelt/pcsensor-temper $tmpdir/temper >> $DEST/debug/temper-build.log 2>&1

	display_alert "... downloading sources" "BT utils" "info"
	git clone -q https://github.com/phelum/CT_Bluetooth $tmpdir/brcm >> $DEST/debug/brcm-build.log 2>&1

	rm -f $tmpdir/brcm/{brcm_patchram_plus,brcm_bt_reset} $tmpdir/brcm/*.o

	pack_to_deb()
	{
		mkdir -p $tmpdir/armbian-tools-${RELEASE}_${REVISION}_${ARCH}/{DEBIAN,usr/bin,/etc/default,/etc/init.d}

		# set up control file
		cat <<-END > $tmpdir/armbian-tools-${RELEASE}_${REVISION}_${ARCH}/DEBIAN/control
		Package: armbian-tools-$RELEASE
		Version: $REVISION
		Architecture: $ARCH
		Maintainer: $MAINTAINER <$MAINTAINERMAIL>
		Installed-Size: 1
		Provides: armbian-tools
		Conflicts: armbian-tools
		Depends: libc6 (>= 2.10), libusb-1.0-0 (>= 2:1.0.8), libusb-0.1-4, libudev1
		Section: utils
		Priority: optional
		Description: Armbian tools, temper, Cubie bt utils
		END
		
		# temper
		cp $tmpdir/temper/src/pcsensor $tmpdir/armbian-tools-${RELEASE}_${REVISION}_${ARCH}/usr/bin/temper
		# brcm
		cp $tmpdir/brcm/{brcm_bt_reset,brcm_patchram_plus} $tmpdir/armbian-tools-${RELEASE}_${REVISION}_${ARCH}/usr/bin
		# brcm configs and service
		install -m 644 $SRC/lib/scripts/brcm40183					$tmpdir/armbian-tools-${RELEASE}_${REVISION}_${ARCH}/etc/default		
		install -m 755	$SRC/lib/scripts/brcm40183-patch			$tmpdir/armbian-tools-${RELEASE}_${REVISION}_${ARCH}/etc/init.d
		
		cd $tmpdir/armbian-tools-${RELEASE}_${REVISION}_${ARCH}
		find . -type f ! -regex '.*.hg.*' ! -regex '.*?debian-binary.*' ! -regex '.*?DEBIAN.*' -printf '%P ' | xargs md5sum > DEBIAN/md5sums
		cd $tmpdir
		dpkg -b armbian-tools-${RELEASE}_${REVISION}_${ARCH} >/dev/null
		mv $tmpdir/armbian-tools-${RELEASE}_${REVISION}_${ARCH}.deb $DEST/debs
		cd $CACHEDIR
		rm -rf $tmpdir
	}

	compiling()
	{
		display_alert "... compiling" "temper" "info"
		chroot $CACHEDIR/sdcard /bin/bash -c "cd /root/tools/temper/src; make clean" >> $DEST/debug/tools-build.log 2>&1
		chroot $CACHEDIR/sdcard /bin/bash -c "cd /root/tools/temper/src; make $CTHREADS" >> $DEST/debug/tools-build.log 2>&1
		if [[ $? -ne 0 || ! -f $tmpdir/temper/src/pcsensor ]]; then
			cd $CACHEDIR
			rm -rf $tmpdir
			display_alert "Error building" "temper" "wrn"
			return
		fi
		display_alert "... compiling" "bluetooth utils" "info"
		chroot $CACHEDIR/sdcard /bin/bash -c "cd /root/tools/brcm; make $CTHREADS" >> $DEST/debug/tools-build.log 2>&1
		if [[ $? -ne 0 || ! -f $tmpdir/brcm/brcm_bt_reset ]]; then
			cd $CACHEDIR
			rm -rf $tmpdir
			display_alert "Error building" "BT utils" "wrn"
			return
		fi
	}

	compiling
	pack_to_deb
}

if [[ ! -f $DEST/debs/armbian-tools-${RELEASE}_${REVISION}_${ARCH}.deb ]]; then
	compile_tools
fi

display_alert "Installing" "armbian-tools-${RELEASE}_${REVISION}_${ARCH}.deb" "info"
chroot $CACHEDIR/sdcard /bin/bash -c "dpkg -i /tmp/debs/armbian-tools-${RELEASE}_${REVISION}_${ARCH}.deb" >> $DEST/debug/tools-build.log
