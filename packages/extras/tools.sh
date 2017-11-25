# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

compile_tools()
{
	local tmpdir=$SDCARD/root/tools

	display_alert "Building deb" "armbian-tools" "info"

	display_alert "... downloading sources" "BT utils" "info"
	git clone -q https://github.com/phelum/CT_Bluetooth $tmpdir/brcm >> $DEST/debug/brcm-build.log 2>&1

	rm -f $tmpdir/brcm/{brcm_patchram_plus,brcm_bt_reset} $tmpdir/brcm/*.o

	display_alert "... compiling" "bluetooth utils" "info"
	chroot $SDCARD /bin/bash -c "cd /root/tools/brcm; make $CTHREADS" >> $DEST/debug/tools-build.log 2>&1
	if [[ $? -ne 0 || ! -f $tmpdir/brcm/brcm_bt_reset ]]; then
		cd $SRC/cache
		rm -rf $tmpdir
		display_alert "Error building" "BT utils" "wrn"
		return
	fi

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
	Depends: libc6 (>= 2.10)
	Section: utils
	Priority: optional
	Description: Armbian tools, Cubie bt utils
	END

	# brcm
	cp $tmpdir/brcm/{brcm_bt_reset,brcm_patchram_plus} $tmpdir/armbian-tools-${RELEASE}_${REVISION}_${ARCH}/usr/bin
	# brcm configs and service
	install -m 644 $SRC/packages/extras/tools/brcm40183 $tmpdir/armbian-tools-${RELEASE}_${REVISION}_${ARCH}/etc/default
	install -m 755	$SRC/packages/extras/tools/brcm40183-patch $tmpdir/armbian-tools-${RELEASE}_${REVISION}_${ARCH}/etc/init.d

	# ap6212 configs and service
	install -m 644 $SRC/packages/extras/tools/ap6212 $tmpdir/armbian-tools-${RELEASE}_${REVISION}_${ARCH}/etc/default
	install -m 755 $SRC/packages/extras/tools/ap6212-bluetooth $tmpdir/armbian-tools-${RELEASE}_${REVISION}_${ARCH}/etc/init.d

	cd $tmpdir/armbian-tools-${RELEASE}_${REVISION}_${ARCH}
	find . -type f ! -regex '.*.hg.*' ! -regex '.*?debian-binary.*' ! -regex '.*?DEBIAN.*' -printf '%P ' | xargs md5sum > DEBIAN/md5sums
	cd $tmpdir
	fakeroot dpkg -b armbian-tools-${RELEASE}_${REVISION}_${ARCH} >/dev/null
	mv $tmpdir/armbian-tools-${RELEASE}_${REVISION}_${ARCH}.deb $DEST/debs
	cd $SRC/cache
	rm -rf $tmpdir
}

if [[ ! -f $DEST/debs/armbian-tools-${RELEASE}_${REVISION}_${ARCH}.deb ]]; then
	compile_tools
fi

install_deb_chroot "$DEST/debs/armbian-tools-${RELEASE}_${REVISION}_${ARCH}.deb"
