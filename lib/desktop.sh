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

	# add loading desktop splash service
	cp $SRC/packages/blobs/desktop/desktop-splash/desktop-splash.service $SDCARD/etc/systemd/system/desktop-splash.service

	# install optimized firefox configuration
	if [[ -d $SDCARD/usr/lib/firefox-esr/ ]]; then
		cp $SRC/packages/blobs/desktop/firefox.conf $SDCARD/usr/lib/firefox-esr/mozilla.cfg
		echo 'pref("general.config.obscure_value", 0);' > 			$SDCARD/usr/lib/firefox-esr/defaults/pref/local-settings.js
		echo 'pref("general.config.filename", "mozilla.cfg");' >> 	$SDCARD/usr/lib/firefox-esr/defaults/pref/local-settings.js
	fi

	# install optimized chromium configuration
	[[ -d $SDCARD/etc/chromium-browser ]] && cp $SRC/packages/blobs/desktop/chromium.conf $SDCARD/etc/chromium-browser/default
	[[ -d $SDCARD/etc/chromium.d ]] && cp $SRC/packages/blobs/desktop/chromium.conf $SDCARD/etc/chromium.d/chromium.conf

	# install default desktop settings
	cp -R $SRC/packages/blobs/desktop/skel/. $SDCARD/etc/skel
	cp -R $SRC/packages/blobs/desktop/skel/. $SDCARD/root

	# install dedicated startup icons
	cp $SRC/packages/blobs/desktop/icons/${DISTRIBUTION,,}.png $SDCARD/usr/share/pixmaps
	sed 's/xenial.png/'${DISTRIBUTION,,}'.png/' -i $SDCARD/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml

	# install wallpapers
	mkdir -p $SDCARD/usr/share/backgrounds/xfce/
	cp $SRC/packages/blobs/desktop/wallpapers/armbian*.jpg $SDCARD/usr/share/backgrounds/xfce/

	# Adjust menu
	sed -i '0,/xfce4-about.desktop/s//armbian-donate.desktop/' $SDCARD/etc/xdg/menus/xfce-applications.menu
	sed -i '/armbian-donate.desktop/a \\t<Filename>armbian-support.desktop</Filename>/' $SDCARD/etc/xdg/menus/xfce-applications.menu

	# Hide few items
	[[ -f $SDCARD/usr/share/applications/display-im6.q16.desktop ]] && mv $SDCARD/usr/share/applications/display-im6.q16.desktop $SDCARD/usr/share/applications/display-im6.q16.desktop.hidden
	[[ -f $SDCARD/usr/share/applications/display-im6.desktop ]] && mv $SDCARD/usr/share/applications/display-im6.desktop $SDCARD/usr/share/applications/display-im6.desktop.hidden
	[[ -f $SDCARD/usr/share/applications/vim.desktop ]] && mv $SDCARD/usr/share/applications/vim.desktop $SDCARD/usr/share/applications/vim.desktop.hidden
	[[ -f $SDCARD/usr/share/applications/libreoffice-startcenter.desktop ]] && mv $SDCARD/usr/share/applications/libreoffice-startcenter.desktop $SDCARD/usr/share/applications/libreoffice-startcenter.desktop.hidden

	# Enable network manager
	if [[ -f $SDCARD/etc/NetworkManager/NetworkManager.conf ]]; then
		sed "s/managed=\(.*\)/managed=true/g" -i $SDCARD/etc/NetworkManager/NetworkManager.conf
		# Disable DNS management withing NM for !Stretch
		[[ $RELEASE != stretch ]] && sed "s/\[main\]/\[main\]\ndns=none/g" -i $SDCARD/etc/NetworkManager/NetworkManager.conf
		printf '[keyfile]\nunmanaged-devices=interface-name:p2p0\n' >> $SDCARD/etc/NetworkManager/NetworkManager.conf
	fi

	# Disable Pulseaudio timer scheduling which does not work with sndhdmi driver
	if [[ -f $SDCARD/etc/pulse/default.pa ]]; then
		sed "s/load-module module-udev-detect$/& tsched=0/g" -i  $SDCARD/etc/pulse/default.pa
	fi

	# Disable desktop mode autostart for now to enforce creation of normal user account
	[[ -f $SDCARD/etc/default/nodm ]] && sed "s/NODM_ENABLED=\(.*\)/NODM_ENABLED=false/g" -i $SDCARD/etc/default/nodm
	[[ -d $SDCARD/etc/lightdm ]] && chroot $SDCARD /bin/bash -c "systemctl --no-reload disable lightdm.service >/dev/null 2>&1"

	# install logo for login screen
	cp $SRC/packages/blobs/desktop/icons/armbian.png $SDCARD/usr/share/pixmaps

	# Compile Turbo Frame buffer for sunxi
	if [[ $LINUXFAMILY == sun* && $BRANCH == default ]]; then
		sed 's/name="use_compositing" type="bool" value="true"/name="use_compositing" type="bool" value="false"/' -i $SDCARD/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
		sed 's/name="use_compositing" type="bool" value="true"/name="use_compositing" type="bool" value="false"/' -i $SDCARD/root/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml

		# enable memory reservations
		echo "disp_mem_reserves=on" >> $SDCARD/boot/armbianEnv.txt
		echo "extraargs=cma=96M" >> $SDCARD/boot/armbianEnv.txt
	fi
}
