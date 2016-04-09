# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of tool chain https://github.com/igorpecovnik/lib
#

# NOTE: NEeds gcc5 specific fixes like other wireless drivers

install_rtl8192cu()
{
	local plugin_repo="https://github.com/dz0ny/rt8192cu"
	# https://github.com/pvaret/rtl8192cu-fixes
	local plugin_dir="rt8192cu"

	fetch_from_github "$plugin_repo" "$plugin_dir"
	cd $SOURCES/$plugin_dir
	#git checkout 0ea77e747df7d7e47e02638a2ee82ad3d1563199
	make ARCH=$ARCHITECTURE CROSS_COMPILE="${CROSS_COMPILE//ccache}" clean >> $DEST/debug/compilation.log
	make ARCH=$ARCHITECTURE CROSS_COMPILE="${CROSS_COMPILE//ccache}" KSRC=$SOURCES/$LINUXSOURCEDIR/ >> $DEST/debug/compilation.log
	cp *.ko $CACHEDIR/sdcard/lib/modules/$VER-$LINUXFAMILY/kernel/net/wireless/
	depmod -b $CACHEDIR/sdcard/ $VER-$LINUXFAMILY
	#cp blacklist*.conf $CACHEDIR/sdcard/etc/modprobe.d/
}

if [[ $BRANCH == default ]]; then
	display_alert "Installing additional driver" "RT8192" "info"
	install_rtl8192cu
fi
