# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

compile_armbian-config()
{
	local tmpdir=$SRC/.tmp/armbian-config_${REVISION}_all

	display_alert "Building deb" "armbian-config" "info"

	fetch_from_repo "https://github.com/armbian/config" "armbian-config" "branch:master"

	mkdir -p $tmpdir/{DEBIAN,usr/bin/,usr/sbin/,usr/lib/armbian-config/}

	# set up control file
	cat <<-END > $tmpdir/DEBIAN/control
	Package: armbian-config
	Version: $REVISION
	Architecture: all
	Maintainer: $MAINTAINER <$MAINTAINERMAIL>
	Replaces: armbian-bsp
	Depends: bash, iperf3, psmisc, curl, bc, expect, dialog, iptables, resolvconf, \
	debconf-utils, unzip, build-essential, html2text, apt-transport-https, html2text, dirmngr, software-properties-common
	Recommends: armbian-bsp
	Suggests: libpam-google-authenticator, qrencode, network-manager, sunxi-tools
	Section: utils
	Priority: optional
	Description: Armbian configuration utility
	END

	install -m 755 $SRC/cache/sources/armbian-config/scripts/tv_grab_file $tmpdir/usr/bin/tv_grab_file
	install -m 755 $SRC/cache/sources/armbian-config/debian-config $tmpdir/usr/sbin/armbian-config
	install -m 644 $SRC/cache/sources/armbian-config/debian-config-jobs $tmpdir/usr/lib/armbian-config/jobs.sh
	install -m 644 $SRC/cache/sources/armbian-config/debian-config-submenu $tmpdir/usr/lib/armbian-config/submenu.sh
	install -m 644 $SRC/cache/sources/armbian-config/debian-config-functions $tmpdir/usr/lib/armbian-config/functions.sh
	install -m 644 $SRC/cache/sources/armbian-config/debian-config-functions-network $tmpdir/usr/lib/armbian-config/functions-network.sh
	install -m 755 $SRC/cache/sources/armbian-config/softy $tmpdir/usr/sbin/softy
	# fallback to replace armbian-config in BSP
	ln -sf /usr/sbin/armbian-config $tmpdir/usr/bin/armbian-config
	ln -sf /usr/sbin/softy $tmpdir/usr/bin/softy

	fakeroot dpkg -b ${tmpdir} >/dev/null
	mv ${tmpdir}.deb $DEST/debs
	rm -rf $tmpdir
}

if [[ ! -f $DEST/debs/armbian-config_${REVISION}_all.deb ]]; then
	compile_armbian-config
fi

# installing additional dependencies here so they are installed only with armbian-config
chroot $SDCARD /bin/bash -c "apt install -q -y iperf3 debconf-utils html2text dirmngr expect libassuan0 libnpth0 libksba8 expect"
install_deb_chroot "$DEST/debs/armbian-config_${REVISION}_all.deb"
