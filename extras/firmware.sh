# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of tool chain https://github.com/igorpecovnik/lib
#

build_firmware()
{
	display_alert "Merging and packaging linux firmware" "@host" "info"
	
	local plugin_repo="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git"
	local plugin_dir="armbian-firmware${FULL}"
	[[ -d "$SOURCES/$plugin_dir" && -n "$SOURCES$plugin_dir" ]] && rm -rf $SOURCES/$plugin_dir
	
	if [[ -n $FULL ]]; then
		fetch_from_repo "$plugin_repo" "$plugin_dir/lib/firmware" "branch:master"
	fi	
	mkdir -p $SOURCES/$plugin_dir/lib/firmware
	# overlay our firmware
	cp -R $SRC/lib/bin/firmware-overlay/* $SOURCES/$plugin_dir/lib/firmware

	# cleanup what's not needed for sure
	rm -rf $SOURCES/$plugin_dir/lib/firmware/{amdgpu,amd-ucode,radeon,nvidia,matrox,.git}
	cd $SOURCES/$plugin_dir

	# set up control file
	mkdir -p DEBIAN
	cat <<-END > DEBIAN/control
	Package: armbian-firmware${FULL}
	Version: $REVISION
	Architecture: $ARCH
	Maintainer: $MAINTAINER <$MAINTAINERMAIL>
	Installed-Size: 1
	Replaces: linux-firmware, firmware-brcm80211, armbian-firmware${REPLACE}
	Section: kernel
	Priority: optional
	Description: Linux firmware${FULL}
	END

	cd $SOURCES
	# pack
	mv armbian-firmware${FULL} armbian-firmware${FULL}_${REVISION}_${ARCH}
	dpkg -b armbian-firmware${FULL}_${REVISION}_${ARCH} >> $DEST/debug/install.log 2>&1
	mv armbian-firmware${FULL}_${REVISION}_${ARCH} armbian-firmware${FULL}
	mv armbian-firmware${FULL}_${REVISION}_${ARCH}.deb $DEST/debs/ || display_alert "Failed moving firmware package" "" "wrn"
}

FULL=""
REPLACE="-full"
[[ ! -f $DEST/debs/armbian-firmware_${REVISION}_${ARCH}.deb ]] && build_firmware
FULL="-full"
REPLACE=""
[[ ! -f $DEST/debs/armbian-firmware${FULL}_${REVISION}_${ARCH}.deb ]] && build_firmware

# install basic firmware by default
display_alert "Installing linux firmware" "$REVISION" "info"
chroot $CACHEDIR/$SDCARD /bin/bash -c "dpkg -i /tmp/debs/armbian-firmware_${REVISION}_${ARCH}.deb" >> $DEST/debug/install.log
