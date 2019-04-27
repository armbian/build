# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

create_desktop_package ()
{
	# cleanup package list
	PACKAGE_LIST_DESKTOP=${PACKAGE_LIST_DESKTOP// /,}; PACKAGE_LIST_DESKTOP=${PACKAGE_LIST_DESKTOP//[[:space:]]/}
	PACKAGE_LIST_DESKTOP_RECOMMENDS=${PACKAGE_LIST_DESKTOP_RECOMMENDS// /,}; PACKAGE_LIST_DESKTOP_RECOMMENDS=${PACKAGE_LIST_DESKTOP_RECOMMENDS//[[:space:]]/}

	local destination=$SRC/.tmp/${RELEASE}/${BOARD}/${CHOSEN_DESKTOP}_${REVISION}_all
	rm -rf $destination
	mkdir -p $destination/DEBIAN

	# set up control file
	cat <<-EOF > $destination/DEBIAN/control
	Package: ${CHOSEN_DESKTOP}
	Version: $REVISION
	Architecture: all
	Maintainer: $MAINTAINER <$MAINTAINERMAIL>
	Installed-Size: 1
	Section: xorg
	Priority: optional
	Depends: ${PACKAGE_LIST_DESKTOP//[:space:]+/,}
	Recommends: ${PACKAGE_LIST_DESKTOP_RECOMMENDS//[:space:]+/,}
	Provides: ${CHOSEN_DESKTOP}
	Description: Armbian desktop for ${DISTRIBUTION} ${RELEASE}
	EOF

	cat <<-EOF > $destination/DEBIAN/postinst
	#!/bin/sh -e

		# overwrite stock chromium and firefox configuration
		if [ -d /etc/chromium-browser/ ]; then ln -sf /etc/armbian/chromium.conf /etc/chromium-browser/default; fi
		if [ -d /etc/chromium.d/ ]; then ln -sf /etc/armbian/chromium.conf /etc/chromium.d/chromium.conf; fi
		cp -R /etc/armbian/chromium /usr/share
		# overwrite stock lightdm greeter configuration
		if [ -d /etc/armbian/lightdm ]; then cp -R /etc/armbian/lightdm /etc/; fi


		if [ -d /usr/lib/firefox-esr/ ]; then
			ln -sf /etc/armbian/firefox.conf /usr/lib/firefox-esr/mozilla.cfg
			echo 'pref("general.config.obscure_value", 0);' > /usr/lib/firefox-esr/defaults/pref/local-settings.js
			echo 'pref("general.config.filename", "mozilla.cfg");' >> /usr/lib/firefox-esr/defaults/pref/local-settings.js
		fi

		# Adjust menu
		sed -i -n '/<Menuname>Settings<\/Menuname>/{p;:a;N;/<Filename>xfce4-session-logout.desktop<\/Filename>/!ba;s/.*\n/\
		\t<Separator\/>\n\t<Merge type="all"\/>\n        <Separator\/>\n        <Filename>armbian-donate.desktop<\/Filename>\
		\n        <Filename>armbian-support.desktop<\/Filename>\n/};p' /etc/xdg/menus/xfce-applications.menu

		# Hide few items
		if [ -f /usr/share/applications/display-im6.q16.desktop ]; then mv /usr/share/applications/display-im6.q16.desktop /usr/share/applications/display-im6.q16.desktop.hidden; fi
		if [ -f /usr/share/applications/display-im6.desktop ]]; then  mv /usr/share/applications/display-im6.desktop /usr/share/applications/display-im6.desktop.hidden; fi
		if [ -f /usr/share/applications/vim.desktop ]]; then  mv /usr/share/applications/vim.desktop /usr/share/applications/vim.desktop.hidden; fi
		if [ -f /usr/share/applications/libreoffice-startcenter.desktop ]]; then mv /usr/share/applications/libreoffice-startcenter.desktop /usr/share/applications/libreoffice-startcenter.desktop.hidden; fi

		# Disable Pulseaudio timer scheduling which does not work with sndhdmi driver
		if [ -f /etc/pulse/default.pa ]; then sed "s/load-module module-udev-detect$/& tsched=0/g" -i  /etc/pulse/default.pa; fi

	exit 0
	EOF
	chmod 755 $destination/DEBIAN/postinst

	# add loading desktop splash service
	mkdir -p $destination/etc/systemd/system/
	cp $SRC/packages/blobs/desktop/desktop-splash/desktop-splash.service $destination/etc/systemd/system/desktop-splash.service

	# install optimized browser configurations
	mkdir -p $destination/etc/armbian
	cp $SRC/packages/blobs/desktop/chromium.conf $destination/etc/armbian
	cp $SRC/packages/blobs/desktop/firefox.conf  $destination/etc/armbian
	cp -R $SRC/packages/blobs/desktop/chromium $destination/etc/armbian

	# install lightdm greeter
	cp -R $SRC/packages/blobs/desktop/lightdm $destination/etc/armbian

	# install default desktop settings
	mkdir -p $destination/etc/skel
	cp -R $SRC/packages/blobs/desktop/skel/. $destination/etc/skel


	# using different icon pack. Workaround due to this bug https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=867779
	if [[ ${RELEASE} == bionic || ${RELEASE} == stretch || ${RELEASE} == buster || ${RELEASE} == disco ]]; then
	sed -i 's/<property name="IconThemeName" type="string" value=".*$/<property name="IconThemeName" type="string" value="Humanity-Dark">/g' \
	$destination/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml
	fi

	# install dedicated startup icons
	mkdir -p $destination/usr/share/pixmaps $destination/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/
	cp $SRC/packages/blobs/desktop/icons/${DISTRIBUTION,,}.png $destination/usr/share/pixmaps
	sed 's/xenial.png/'${DISTRIBUTION,,}'.png/' -i $destination/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml

	# install logo for login screen
	cp $SRC/packages/blobs/desktop/icons/armbian.png $destination/usr/share/pixmaps

	# install wallpapers
	mkdir -p $destination/usr/share/backgrounds/xfce/
	cp $SRC/packages/blobs/desktop/wallpapers/armbian*.jpg $destination/usr/share/backgrounds/xfce/

	# create board DEB file
	display_alert "Building desktop package" "${CHOSEN_DESKTOP}_${REVISION}_all" "info"
	fakeroot dpkg-deb -b $destination ${destination}.deb >/dev/null
	mkdir -p ${DEST}/debs/${RELEASE}
	mv ${destination}.deb $DEST/debs/${RELEASE}
	# cleanup
	rm -rf $destination
}

desktop_postinstall ()
{
	# stage: install display manager
	[[ -f $SDCARD/etc/default/nodm ]] && sed "s/NODM_ENABLED=\(.*\)/NODM_ENABLED=false/g" -i $SDCARD/etc/default/nodm
	[[ -d $SDCARD/etc/lightdm ]] && chroot $SDCARD /bin/bash -c "systemctl --no-reload disable lightdm.service >/dev/null 2>&1"

	# Compile Turbo Frame buffer for sunxi
	if [[ $LINUXFAMILY == sun* && $BRANCH == default ]]; then
		sed 's/name="use_compositing" type="bool" value="true"/name="use_compositing" type="bool" value="false"/' -i $SDCARD/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml

		# enable memory reservations
		echo "disp_mem_reserves=on" >> $SDCARD/boot/armbianEnv.txt
		echo "extraargs=cma=96M" >> $SDCARD/boot/armbianEnv.txt
	fi

	mkdir -p $SDCARD/etc/skel/Desktop/
	cp $SRC/cache/SRC/Test* $SDCARD/etc/skel/Desktop

}
