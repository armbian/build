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

install_desktop ()
{
	display_alert "Installing desktop" "XFCE" "info"

	# add loading desktop splash service
	cp $SRC/packages/blobs/desktop/desktop-splash/desktop-splash.service $CACHEDIR/$SDCARD/etc/systemd/system/desktop-splash.service

	if [[ $RELEASE == xenial ]]; then
		# install optimized firefox configuration
		# cp $SRC/config/firefox.conf $CACHEDIR/$SDCARD/etc/firefox/syspref.js
		# install optimized chromium configuration
		cp $SRC/config/chromium.conf $CACHEDIR/$SDCARD/etc/chromium-browser/default
	fi
	# install dedicated startup icons
	cp $SRC/packages/blobs/desktop/icons/${RELEASE}.png $CACHEDIR/$SDCARD/usr/share/pixmaps

	# install default desktop settings
	cp -R $SRC/packages/blobs/desktop/skel/. $CACHEDIR/$SDCARD/etc/skel
	cp -R $SRC/packages/blobs/desktop/skel/. $CACHEDIR/$SDCARD/root

	# install wallpapers
	mkdir -p $CACHEDIR/$SDCARD/usr/share/backgrounds/xfce/
	cp $SRC/packages/blobs/desktop/wallpapers/armbian*.jpg $CACHEDIR/$SDCARD/usr/share/backgrounds/xfce/

	# Install custom icons and theme
	cp $SRC/packages/blobs/desktop/vibrancy-colors_2.4-trusty-Noobslab.com_all.deb $CACHEDIR/$SDCARD/tmp/
	chroot $CACHEDIR/$SDCARD /bin/bash -c "dpkg -i /tmp/vibrancy-colors_2.4-trusty-Noobslab.com_all.deb >/dev/null 2>&1"
	rm -f $CACHEDIR/$SDCARD/tmp/*.deb

	# Enable network manager
	if [[ -f $CACHEDIR/$SDCARD/etc/NetworkManager/NetworkManager.conf ]]; then
		sed "s/managed=\(.*\)/managed=true/g" -i $CACHEDIR/$SDCARD/etc/NetworkManager/NetworkManager.conf
		# Disable dns management withing NM
		sed "s/\[main\]/\[main\]\ndns=none/g" -i $CACHEDIR/$SDCARD/etc/NetworkManager/NetworkManager.conf
		printf '[keyfile]\nunmanaged-devices=interface-name:p2p0\n' >> $CACHEDIR/$SDCARD/etc/NetworkManager/NetworkManager.conf
	fi

	# Disable Pulseaudio timer scheduling which does not work with sndhdmi driver
	if [[ -f $CACHEDIR/$SDCARD/etc/pulse/default.pa ]]; then
		sed "s/load-module module-udev-detect$/& tsched=0/g" -i  $CACHEDIR/$SDCARD/etc/pulse/default.pa
	fi

	# Disable desktop mode autostart for now to enforce creation of normal user account
	sed "s/NODM_ENABLED=\(.*\)/NODM_ENABLED=false/g" -i $CACHEDIR/$SDCARD/etc/default/nodm

	# Compile Turbo Frame buffer for sunxi
	if [[ $LINUXFAMILY == sun* && $BRANCH == default ]]; then
		sed 's/name="use_compositing" type="bool" value="true"/name="use_compositing" type="bool" value="false"/' -i $CACHEDIR/$SDCARD/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
		sed 's/name="use_compositing" type="bool" value="true"/name="use_compositing" type="bool" value="false"/' -i $CACHEDIR/$SDCARD/root/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml

		# enable memory reservations
		echo "disp_mem_reserves=on" >> $CACHEDIR/$SDCARD/boot/armbianEnv.txt
	fi
}
