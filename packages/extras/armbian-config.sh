# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

compile_armbian-config()
{
	local tmpdir=$SRC/.tmp/armbian-config_${REVISION}_all/

	display_alert "Building deb" "armbian-config" "info"

	fetch_from_repo "https://github.com/armbian/config" "armbian-config" "branch:dev"

	mkdir -p $tmpdir/{DEBIAN,/usr/bin/}

	# set up control file
	cat <<-END > $tmpdir/DEBIAN/control
	Package: armbian-config
	Version: $REVISION
	Architecture: all
	Maintainer: $MAINTAINER <$MAINTAINERMAIL>
	Replaces: armbian-bsp
	Depends: bc, expect, rcconf, dialog, network-manager
	Section: utils
	Priority: optional
	Description: Armbian configuration utility
	END

	install -m 755 $SRC/cache/sources/armbian-config/scripts/tv_grab_file $tmpdir/usr/bin/tv_grab_file
	install -m 755 $SRC/cache/sources/armbian-config/debian-config $tmpdir/usr/bin/armbian-config
	install -m 644 $SRC/cache/sources/armbian-config/debian-config-jobs $tmpdir/usr/bin/armbian-config-jobs
	install -m 644 $SRC/cache/sources/armbian-config/debian-config-submenu $tmpdir/usr/bin/armbian-config-submenu
	install -m 755 $SRC/cache/sources/armbian-config/softy $tmpdir/usr/bin/softy

	cd $tmpdir
	fakeroot dpkg -b ${tmpdir} ${tmpdir}.deb
	mv ${tmpdir}.deb $DEST/debs
	rm -rf $tmpdir
}

if [[ ! -f $DEST/debs/armbian-config_${REVISION}_all.deb ]]; then
	compile_armbian-config
fi

install_deb_chroot "$DEST/debs/armbian-config_${REVISION}_all.deb"
