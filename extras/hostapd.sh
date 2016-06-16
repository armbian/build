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

compile_hostapd()
{
	display_alert "Building deb" "hostapd" "info"

	local tmpdir="$CACHEDIR/sdcard/root/hostapd"

	mkdir -p $tmpdir

	if [[ -d $tmpdir/hostap ]]; then
		cd $tmpdir/hostap
		display_alert "Updating sources" "hostapd" "info"
		git checkout -f -q master
		git pull -q
	else
		display_alert "Downloading sources" "hostapd" "info"
		# TODO: Replace with fetch_from_github
		git clone -q git://w1.fi/hostap.git $tmpdir/hostap
	fi

	pack_to_deb()
	{
		chroot $CACHEDIR/sdcard /bin/bash -c "cd /root/hostapd; apt-get -qq download hostapd > /dev/null 2>&1"
		cd $tmpdir
		#apt-get -qq download hostapd > /dev/null 2>&1
		dpkg-deb -R hostapd*.deb armbian-hostapd-${RELEASE}_${REVISION}_${ARCH}
		rm hostapd*.deb

		# set up control file
		cat <<-END > armbian-hostapd-${RELEASE}_${REVISION}_${ARCH}/DEBIAN/control
		Package: armbian-hostapd-$RELEASE
		Version: $REVISION
		Architecture: $ARCH
		Maintainer: $MAINTAINER <$MAINTAINERMAIL>
		Installed-Size: 1
		Section: net
		Depends: libc6, libnl-3-200, libnl-genl-3-200, libssl1.0.0
		Provides: armbian-hostapd
		Conflicts: armbian-hostapd, hostapd
		Priority: optional
		Description: Patched hostapd for $RELEASE
		END

		cp $tmpdir/hostap/hostapd/{hostapd,hostapd-rt,hostapd_cli,hostapd_cli-rt} armbian-hostapd-${RELEASE}_${REVISION}_${ARCH}/usr/sbin

		cd armbian-hostapd-${RELEASE}_${REVISION}_${ARCH}
		find . -type f ! -regex '.*.hg.*' ! -regex '.*?debian-binary.*' ! -regex '.*?DEBIAN.*' -printf '%P ' | xargs md5sum > DEBIAN/md5sums
		cd ..
		dpkg -b armbian-hostapd-${RELEASE}_${REVISION}_${ARCH} >/dev/null
		mv *.deb $DEST/debs
		cd $CACHEDIR
		rm -rf $tmpdir
	}

	compiling()
	{
		chroot $CACHEDIR/sdcard /bin/bash -c "cd /root/hostapd/hostap/hostapd; make clean" >> $DEST/debug/hostapd-build.log 2>&1
		chroot $CACHEDIR/sdcard /bin/bash -c "cd /root/hostapd/hostap/hostapd; make $CTHREADS" >> $DEST/debug/hostapd-build.log 2>&1
		if [[ $? -ne 0 || ! -f $tmpdir/hostap/hostapd/hostapd ]]; then
			cd $CACHEDIR
			rm -rf $tmpdir
			exit_with_error "Error building" "hostapd"
		fi
	}

	patching()
	{
		# Other usefull patches:
		# https://dev.openwrt.org/browser/trunk/package/network/services/hostapd/patches?order=name

		cp $SRC/lib/config/hostapd/files/*.* $tmpdir/hostap/src/drivers/

		cd $tmpdir/hostap
		# brute force for 40Mhz
		if [[ -z $(patch --dry-run -t -p1 < $SRC/lib/config/hostapd/patch/300-noscan.patch | grep previ) ]]; then
			patch --batch -f -p1 < $SRC/lib/config/hostapd/patch/300-noscan.patch >> $DEST/debug/hostapd-build.log 2>&1
		fi
		# patch for realtek
		if [[ $1 == realtek ]]; then
			cp $SRC/lib/config/hostapd/config/config_realtek $tmpdir/hostap/hostapd/.config
			patch --batch -f -p1 < $SRC/lib/config/hostapd/patch/realtek.patch >> $DEST/debug/hostapd-build.log 2>&1
		else
			cp $SRC/lib/config/hostapd/config/config_default $tmpdir/hostap/hostapd/.config
			if ! grep -q rtl871 $tmpdir/hostap/hostapd/main.c ; then
				patch --batch -t -p1 < $SRC/lib/config/hostapd/patch/realtek.patch >> $DEST/debug/hostapd-build.log 2>&1
			fi
		fi
	}

	checkout()
	{
		cd $tmpdir/hostap
		if [[ $1 == stable ]]; then
			git checkout -f -q "hostap_2_5" >> $DEST/debug/hostapd-build.log 2>&1
		else
			git checkout -f -q >> $DEST/debug/hostapd-build.log 2>&1
		fi
	}

	checkout "stable"
	local apver=$(grep '#define VERSION_STR ' $tmpdir/hostap/src/common/version.h | awk '{ print $3 }' | sed 's/\"//g')

	display_alert "Compiling hostapd" "v$apver" "info"

	patching "realtek"
	compiling

	mv $tmpdir/hostap/hostapd/hostapd $tmpdir/hostap/hostapd/hostapd-rt
	mv $tmpdir/hostap/hostapd/hostapd_cli $tmpdir/hostap/hostapd/hostapd_cli-rt

	checkout "stable"
	patching
	compiling

	pack_to_deb
}

[[ ! -f $DEST/debs/armbian-hostapd-${RELEASE}_${REVISION}_${ARCH}.deb ]] && compile_hostapd

display_alert "Installing" "armbian-hostapd-${RELEASE}_${REVISION}_${ARCH}.deb" "info"
chroot $CACHEDIR/sdcard /bin/bash -c "dpkg -r hostapd" >> $DEST/debug/output.log
chroot $CACHEDIR/sdcard /bin/bash -c "dpkg -i /tmp/armbian-hostapd-${RELEASE}_${REVISION}_${ARCH}.deb" >> $DEST/debug/output.log
