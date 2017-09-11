# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

install_desktop ()
{
	display_alert "Installing desktop" "XFCE" "info"

	# temporally. move to configuration.sh once this file gets in action
	PACKAGE_LIST_DESKTOP="$PACKAGE_LIST_DESKTOP vibrancy-colors"

	# cleanup package list
	PACKAGE_LIST_DESKTOP=${PACKAGE_LIST_DESKTOP// /,}; PACKAGE_LIST_DESKTOP=${PACKAGE_LIST_DESKTOP//[[:space:]]/}

	local destination=$SRC/.tmp/armbian-desktop_${REVISION}_${ARCH}
	rm -rf $destination
	mkdir -p $destination/DEBIAN

	# set up control file
	cat <<-EOF > $destination/DEBIAN/control
	Package: armbian-desktop
	Version: $REVISION
	Architecture: $ARCH
	Maintainer: $MAINTAINER <$MAINTAINERMAIL>
	Installed-Size: 1
	Section: kernel
	Priority: optional
	Depends: ${PACKAGE_LIST_DESKTOP//[:space:]+/,}
	Provides: armbian-desktop
	Description: Armbian generic desktop
	EOF

	# set up pre install script
	cat <<-EOF > $destination/DEBIAN/postinst
	#!/bin/sh
	source /etc/armbian-release
	mv /etc/chromium-browser/armbian /etc/chromium-browser/default
	# Disable Pulseaudio timer scheduling which does not work with sndhdmi driver
	if [ -f /etc/pulse/default.pa ]; then sed "s/load-module module-udev-detect$/& tsched=0/g" -i /etc/pulse/default.pa; fi
	# Enable network manager
	if [ -f /etc/NetworkManager/NetworkManager.conf ]]; then
		sed "s/managed=\(.*\)/managed=true/g" -i /etc/NetworkManager/NetworkManager.conf
		# Disable dns management withing NM
		sed "s/\[main\]/\[main\]\ndns=none/g" -i /etc/NetworkManager/NetworkManager.conf
		printf '[keyfile]\nunmanaged-devices=interface-name:p2p0\n' >> /etc/NetworkManager/NetworkManager.conf
	fi
	# Compile Turbo Frame buffer for sunxi
	if [ $LINUXFAMILY = sun4i ] || [ $LINUXFAMILY = sun7i ] || [ $LINUXFAMILY = sun8i ] && [ $BRANCH = next ];
		sed 's/name="use_compositing" type="bool" value="true"/name="use_compositing" type="bool" value="false"/' -i /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
		sed 's/name="use_compositing" type="bool" value="true"/name="use_compositing" type="bool" value="false"/' -i /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
		if [ -n "$SUDO_USER" ]; then
			sed 's/name="use_compositing" type="bool" value="true"/name="use_compositing" type="bool" value="false"/' -i /${SUDO_USER}/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml;
		fi
		# enable memory reservations
		if ! grep disp_mem_reserves /boot/armbianEnv.txt; echo "disp_mem_reserves=on" >> /boot/armbianEnv.txt; fi
	fi
	# copy skel to sudo user
	if [ -n "$SUDO_USER" ]; then cp -R /etc/skel /home/$SUDO_USER; fi
	# TODO: change ownership/fix permissions
	exit 0
	EOF
	chmod 755 $destination/DEBIAN/postinst

	# add loading desktop splash service
	mkdir -p $destination/etc/systemd/system/
	cp $SRC/packages/blobs/desktop/desktop-splash/desktop-splash.service $destination/etc/systemd/system/desktop-splash.service

	# install optimized chromium configuration
	mkdir -p $destination/etc/chromium-browser
	cp $SRC/config/chromium.conf $destination/etc/chromium-browser/armbian

	# install default desktop settings
	mkdir -p $destination/etc/skel $destination/root
	cp -R $SRC/packages/blobs/desktop/skel/. $destination/etc/skel
	cp -R $SRC/packages/blobs/desktop/skel/. $destination/root

	# install dedicated startup icons
	mkdir -p $destination/usr/share/pixmaps $destination/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/
	cp $SRC/packages/blobs/desktop/icons/${DISTRIBUTION,,}.png $destination/usr/share/pixmaps
	sed 's/xenial.png/'${DISTRIBUTION,,}'.png/' -i $destination/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
	# install logo for login screen
	cp $SRC/packages/blobs/desktop/icons/armbian.png $destination/usr/share/pixmaps

	# install wallpapers
	mkdir -p $destination/usr/share/backgrounds/xfce/
	cp $SRC/packages/blobs/desktop/wallpapers/armbian*.jpg $destination/usr/share/backgrounds/xfce/

	# Disable desktop mode autostart for now to enforce creation of normal user account
	[[ -f $SDCARD/etc/default/nodm ]] && sed "s/NODM_ENABLED=\(.*\)/NODM_ENABLED=false/g" -i $SDCARD/etc/default/nodm
	[[ -d $SDCARD/etc/lightdm ]] && chroot $SDCARD /bin/bash -c "systemctl --no-reload disable lightdm.service >/dev/null 2>&1"


	# create board DEB file
	display_alert "Building Armbian desktop package" "$CHOSEN_ROOTFS" "info"
	fakeroot dpkg-deb -b $destination ${destination}.deb
	mkdir -p $DEST/debs/
	mv ${destination}.deb $DEST/debs/
	# cleanup
	rm -rf $destination
}
