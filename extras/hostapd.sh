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


compile_hostapd ()
{
	sync
	echo "Building hostapd" > $DEST/debug/hostapd-build.log 2>&1
	display_alert "Building deb" "hostapd" "info"

	local tmpdir="sdcard/tmp/hostap"

	if [ -d "$CACHEDIR/$tmpdir" ]; then
		cd $CACHEDIR/$tmpdir		
		git checkout -f -q master >> $DEST/debug/hostapd-build.log 2>&1
		git pull -q
		display_alert "Updating sources" "hostapd" "info"		
	else
		display_alert "Downloading sources" "hostapd" "info"		
		git clone -q git://w1.fi/hostap.git $CACHEDIR/$tmpdir >> $DEST/debug/hostapd-build.log 2>&1
	fi


	pack_to_deb ()
	{
		cd $CACHEDIR/sdcard/tmp
		apt-get -qq -d install hostapd
		dpkg-deb -R /var/cache/apt/archives/hostapd* armbian-hostapd${TARGET}"_"${REVISION}_${ARCH}

		# set up control file
cat <<END > armbian-hostapd${TARGET}_${REVISION}_${ARCH}/DEBIAN/control
Package: armbian-hostapd$TARGET
Version: $REVISION
Architecture: $ARCH
Maintainer: $MAINTAINER <$MAINTAINERMAIL>
Installed-Size: 1
Section: kernel
Conflicts: hostapd
Priority: optional
Description: Patched hostapd
END
#

		cp "$CACHEDIR/$tmpdir/hostapd/hostapd" 			armbian-hostapd${TARGET}_${REVISION}_${ARCH}/usr/sbin
		cp "$CACHEDIR/$tmpdir/hostapd/hostapd-rt" 		armbian-hostapd${TARGET}_${REVISION}_${ARCH}/usr/sbin
		cp "$CACHEDIR/$tmpdir/hostapd/hostapd_cli"  	armbian-hostapd${TARGET}_${REVISION}_${ARCH}/usr/sbin
		cp "$CACHEDIR/$tmpdir/hostapd/hostapd_cli-rt" 	armbian-hostapd${TARGET}_${REVISION}_${ARCH}/usr/sbin

		cd armbian-hostapd${TARGET}_${REVISION}_${ARCH}
		find . -type f ! -regex '.*.hg.*' ! -regex '.*?debian-binary.*' ! -regex '.*?DEBIAN.*' -printf '%P ' | xargs md5sum > DEBIAN/md5sums
		cd ..
		dpkg -b armbian-hostapd${TARGET}_${REVISION}_${ARCH} >/dev/null 2>&1
		rm -rf armbian-hostapd${TARGET}_${REVISION}_${ARCH}
	}
	
	
	compiling ()
	{	
		chroot $CACHEDIR/sdcard /bin/bash -c "cd /tmp/hostap/hostapd; make clean" >> $DEST/debug/hostapd-build.log 2>&1
		chroot $CACHEDIR/sdcard /bin/bash -c "cd /tmp/hostap/hostapd; make $CTHREADS" >> $DEST/debug/hostapd-build.log 2>&1	
		if [ $? -ne 0 ] || [ ! -f $CACHEDIR/$tmpdir/hostapd/hostapd ]; then
			display_alert "Not built" "hostapd" "err"
			exit 1
		fi
	}


	patching ()
	{
		# Other usefull patches:
		# https://dev.openwrt.org/browser/trunk/package/network/services/hostapd/patches?order=name

		cp $SRC/lib/config/hostapd/files/*.* $CACHEDIR/$tmpdir/src/drivers/

		# brute force for 40Mhz
		if [ "$(patch --dry-run -t -p1 < $SRC/lib/config/hostapd/patch/300-noscan.patch | grep previ)" == "" ]; then
			patch --batch -f -p1 < $SRC/lib/config/hostapd/patch/300-noscan.patch >> $DEST/debug/hostapd-build.log 2>&1
		fi
		# patch for realtek
		if [ "$1" == "realtek" ]; then
			cp $SRC/lib/config/hostapd/config/config_realtek $CACHEDIR/$tmpdir/hostapd/.config
			patch --batch -f -p1 < $SRC/lib/config/hostapd/patch/realtek.patch >> $DEST/debug/hostapd-build.log 2>&1
		else
			cp $SRC/lib/config/hostapd/config/config_default $CACHEDIR/$tmpdir/hostapd/.config
			if [ "$(cat $CACHEDIR/$tmpdir/hostapd/main.c | grep rtl871)" != "" ]; then
				patch --batch -t -p1 < $SRC/lib/config/hostapd/patch/realtek.patch >> $DEST/debug/hostapd-build.log 2>&1
			fi
		fi
	}


	checkout ()
	{
		if [ "$1" == "stable" ]; then
			cd $CACHEDIR/$tmpdir
			git checkout -f -q "hostap_2_5" >> ../build.log 2>&1
		else
			git checkout -f -q >> ../build.log 2>&1
		fi
	}


	
	checkout "stable"
	local apver=$(cat $CACHEDIR/$tmpdir/src/common/version.h | grep "#define VERSION_STR " | awk '{ print $3 }' | sed 's/\"//g')
	
	display_alert "Compiling" "v$apver" "info"
	
	patching	
	compiling
		mv $CACHEDIR/$tmpdir/hostapd/hostapd 		$CACHEDIR/$tmpdir/hostapd/hostapd-rt
		mv $CACHEDIR/$tmpdir/hostapd/hostapd_cli 	$CACHEDIR/$tmpdir/hostapd/hostapd_cli-rt
	checkout "stable"
	patching 
	compiling
	pack_to_deb

	display_alert "Installing" "armbian-hostapd${TARGET}_${REVISION}_${ARCH}.deb" "info"
	chroot $CACHEDIR/sdcard /bin/bash -c "dpkg -i /tmp/armbian-hostapd${TARGET}_${REVISION}_${ARCH}.deb" >> $DEST/debug/hostapd-build.log 2>&1 
	mv $CACHEDIR/sdcard/tmp/armbian-hostapd${TARGET}_${REVISION}_${ARCH}.deb $DEST/debs
}


if [[ -f "$DEST/debs/armbian-hostapd${TARGET}_${REVISION}_${ARCH}.deb" ]]; then
	# install
	echo "Installing hostapd" > $DEST/debug/hostapd-build.log 2>&1
	display_alert "Installing" "armbian-hostapd${TARGET}_${REVISION}_${ARCH}.deb" "info"
	cp $DEST/debs/armbian-hostapd${TARGET}_${REVISION}_${ARCH}.deb $CACHEDIR/sdcard/tmp
	chroot $CACHEDIR/sdcard /bin/bash -c "dpkg -i /tmp/armbian-hostapd${TARGET}_${REVISION}_${ARCH}.deb" >> $DEST/debug/hostapd-build.log 2>&1 
else
	# compile
	compile_hostapd
fi