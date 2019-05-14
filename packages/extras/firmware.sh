# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

build_firmware()
{
	display_alert "Merging and packaging linux firmware" "@host" "info"

	local plugin_repo="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git"
	local plugin_dir="armbian-firmware${FULL}"
	[[ -d $SRC/cache/sources/$plugin_dir ]] && rm -rf $SRC/cache/sources/$plugin_dir
	mkdir -p $SRC/cache/sources/$plugin_dir/lib/firmware

	fetch_from_repo "https://github.com/armbian/firmware" "armbian-firmware-git" "branch:master"
	if [[ -n $FULL ]]; then
		fetch_from_repo "$plugin_repo" "linux-firmware-git" "branch:master"
		# cp : create hardlinks
		cp -alf $SRC/cache/sources/linux-firmware-git/* $SRC/cache/sources/$plugin_dir/lib/firmware/
	fi
	# overlay our firmware
	# cp : create hardlinks
	cp -alf $SRC/cache/sources/armbian-firmware-git/* $SRC/cache/sources/$plugin_dir/lib/firmware/

	# cleanup what's not needed for sure
	rm -rf $SRC/cache/sources/$plugin_dir/lib/firmware/{amdgpu,amd-ucode,radeon,nvidia,matrox,.git}
	cd $SRC/cache/sources/$plugin_dir

	# set up control file
	mkdir -p DEBIAN
	cat <<-END > DEBIAN/control
	Package: armbian-firmware${FULL}
	Version: $REVISION
	Architecture: all
	Maintainer: $MAINTAINER <$MAINTAINERMAIL>
	Installed-Size: 1
	Replaces: linux-firmware, firmware-brcm80211, firmware-ralink, firmware-samsung, firmware-realtek, armbian-firmware${REPLACE}
	Section: kernel
	Priority: optional
	Description: Linux firmware${FULL}
	END

	cd $SRC/cache/sources
	# pack
	ln -s armbian-firmware${FULL} armbian-firmware${FULL}_${REVISION}_all
	fakeroot dpkg -b armbian-firmware${FULL}_${REVISION}_all >> $DEST/debug/install.log 2>&1
	rm armbian-firmware${FULL}_${REVISION}_all
	mv armbian-firmware${FULL}_${REVISION}_all.deb $DEST/debs/ || display_alert "Failed moving firmware package" "" "wrn"
}

FULL=""
REPLACE="-full"
[[ ! -f $DEST/debs/armbian-firmware_${REVISION}_all.deb ]] && build_firmware
FULL="-full"
REPLACE=""
[[ ! -f $DEST/debs/armbian-firmware${FULL}_${REVISION}_all.deb ]] && build_firmware

# install basic firmware by default
install_deb_chroot "$DEST/debs/armbian-firmware_${REVISION}_all.deb"
