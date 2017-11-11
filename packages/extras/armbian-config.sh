# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

compile_armbian-config()
{
	local tmpdir=$SDCARD/root/config

	display_alert "Building deb" "armbian-config" "info"

	display_alert "... downloading sources" "config" "info"
	git clone -q https://github.com/armbian/config $tmpdir/config >> $DEST/debug/armbian-config.log 2>&1

	pack_to_deb()
	{
		mkdir -p $tmpdir/armbian-config_${REVISION}_all/{DEBIAN,/usr/bin/}

		# set up control file
		cat <<-END > $tmpdir/armbian-config_${REVISION}_all/DEBIAN/control
		Package: armbian-config
		Version: $REVISION
		Architecture: all
		Maintainer: $MAINTAINER <$MAINTAINERMAIL>
		Installed-Size: 1
		Provides: armbian-config
		Conflicts: armbian-config
		Depends: bc, expect, rcconf, dialog, network-manager
		Section: utils
		Priority: optional
		Description: Armbian configuration utility
		END


		install -m 755	$tmpdir/config/debian-config $tmpdir/armbian-config_${REVISION}_all/usr/bin/armbian-config
		install -m 644	$tmpdir/config/debian-config-jobs $tmpdir/armbian-config_${REVISION}_all/usr/bin/armbian-config-jobs
		install -m 644	$tmpdir/config/debian-config-submenu $tmpdir/armbian-config_${REVISION}_all/usr/bin/armbian-config-submenu

		cd $tmpdir/armbian-config_${REVISION}_all
		find . -type f ! -regex '.*.hg.*' ! -regex '.*?debian-binary.*' ! -regex '.*?DEBIAN.*' -printf '%P ' | xargs md5sum > DEBIAN/md5sums
		cd $tmpdir
		fakeroot dpkg -b armbian-config_${REVISION}_all >/dev/null
		mv $tmpdir/armbian-config_${REVISION}_all.deb $DEST/debs
		cd $SRC/cache
		rm -rf $tmpdir
	}

	pack_to_deb
}

if [[ ! -f $DEST/debs/armbian-config_${REVISION}_all.deb ]]; then
	compile_armbian-config
fi

install_deb_chroot "$DEST/debs/armbian-config_${REVISION}_all.deb"
