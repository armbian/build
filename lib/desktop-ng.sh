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

	local destination=$SRC/.tmp/armbian-desktop-${RELEASE}_${REVISION}_all
	rm -rf $destination
	mkdir -p $destination/DEBIAN

	# set up control file
	cat <<-EOF > $destination/DEBIAN/control
	Package: armbian-desktop-${RELEASE}
	Version: $REVISION
	Architecture: all
	Maintainer: $MAINTAINER <$MAINTAINERMAIL>
	Installed-Size: 1
	Section: xorg
	Priority: optional
	Depends: ${PACKAGE_LIST_DESKTOP//[:space:]+/,}
	Provides: armbian-desktop-${RELEASE}
	Description: Armbian generic desktop
	EOF

	# set up templates
	cat <<-EOF > $destination/DEBIAN/templates
	Template: armbian-desktop-stretch/desktop_username
	Type: string
	Description: Please provide or create a username under which a desktop should run.

	Template: armbian-desktop-stretch/desktop_password
	Type: password
	Description: Choose a password.

	Template: armbian-desktop-stretch/desktop_fullname
	Type: string
Description: Your full name (eg. John Doe)
	EOF

	# set up a config file
	cat <<-EOF > $destination/DEBIAN/config
	#!/bin/sh -e

	# Source debconf library.
	. /usr/share/debconf/confmodule
	db_version 2.0

	# This conf script is capable of backing up
	db_capb backup

	STATE=1
	while [ "\$STATE" != 0 -a "\$STATE" != 4 ]; do
	case "\$STATE" in
	1)
	# Ask for username
	db_input high armbian-desktop-stretch/desktop_username || true
	;;

	2)
	# Ask for password
	db_input high armbian-desktop-stretch/desktop_password || true
	;;

	3)
	# Ask for full name
	db_input high armbian-desktop-stretch/desktop_fullname || true
	;;
	esac

	if db_go; then
	STATE=\$((\$STATE + 1))
	else
	STATE=\$((\$STATE - 1))
	fi
	done
	EOF
	chmod 755 $destination/DEBIAN/config

	cat <<-EOF > $destination/DEBIAN/postinst
	#!/bin/sh -e
	. /usr/share/debconf/confmodule
	db_version 2.0

	case "\$1" in
	configure)
	   if db_get armbian-desktop-stretch/desktop_username; then
				RealUserName="\$RET"
	   fi

	   if db_get armbian-desktop-stretch/desktop_password; then
				RealUserPass="\$RET"
	   fi

	   if db_get armbian-desktop-stretch/desktop_fullname; then
				RealUserFull="\$RET"
	   fi

	   # check if exist
	   if [ -z "\$(getent passwd \${RealUserName})" ]; then
				echo "Trying to add user \${RealUserName}"
				adduser \${RealUserName} --gecos "\${RealUserFull}" --disabled-password
				echo "\${RealUserName}:\${RealUserPass}" | sudo chpasswd
			else
				echo "Username \${RealUserName} exists."
		fi

		# add user to groups
		for additionalgroup in sudo netdev audio video dialout plugdev bluetooth systemd-journal ssh; do
				usermod -aG \${additionalgroup} \${RealUserName} 2>/dev/null
		done

		# overwrite stock chromium and firefox configuration
		if [ -d /etc/chromium-browser/ ]; then ln -sf /etc/armbian/chromium.conf /etc/chromium-browser/default; fi
		if [ -d /etc/chromium.d/ ]; then ln -sf /etc/armbian/chromium.conf /etc/chromium.d/chromium.conf; fi
		if [ -d /usr/lib/firefox-esr/ ]; then
				ln -sf /etc/armbian/firefox.conf /usr/lib/firefox-esr/mozilla.cfg
				echo 'pref("general.config.obscure_value", 0);' > /usr/lib/firefox-esr/defaults/pref/local-settings.js
				echo 'pref("general.config.filename", "mozilla.cfg");' >> /usr/lib/firefox-esr/defaults/pref/local-settings.js
		fi



		# Adjust menu
		sed -i '0,/xfce4-about.desktop/s//armbian-donate.desktop/' /etc/xdg/menus/xfce-applications.menu
		sed -i '/armbian-donate.desktop/a \\t<Filename>armbian-support.desktop</Filename>/' /etc/xdg/menus/xfce-applications.menu

		# Hide few items
		if [ -f $SDCARD/usr/share/applications/display-im6.q16.desktop ]; then mv /usr/share/applications/display-im6.q16.desktop /usr/share/applications/display-im6.q16.desktop.hidden; fi
		if [ -f $SDCARD/usr/share/applications/display-im6.desktop ]]; then  mv /usr/share/applications/display-im6.desktop /usr/share/applications/display-im6.desktop.hidden; fi
		if [ -f $SDCARD/usr/share/applications/vim.desktop ]]; then  mv /usr/share/applications/vim.desktop /usr/share/applications/vim.desktop.hidden; fi
		if [ -f $SDCARD/usr/share/applications/libreoffice-startcenter.desktop ]]; then mv /usr/share/applications/libreoffice-startcenter.desktop /usr/share/applications/libreoffice-startcenter.desktop.hidden; fi

		# fix for gksu in Xenial
		touch /home/\${RealUserName}/.Xauthority
		chown \${RealUserName}:\${RealUserName} /home/\${RealUserName}/.Xauthority

		# Disable Pulseaudio timer scheduling which does not work with sndhdmi driver
		if [ -f /etc/pulse/default.pa ]; then sed "s/load-module module-udev-detect$/& tsched=0/g" -i  /etc/pulse/default.pa; fi

		# set up profile sync daemon on desktop systems
		which psd >/dev/null 2>&1
		if [ \$? -eq 0 ]; then
			echo "\${RealUserName} ALL=(ALL) NOPASSWD: /usr/bin/psd-overlay-helper" >> /etc/sudoers
			touch /home/\${RealUserName}/.activate_psd
			chown \${RealUserName}:\${RealUserName} /home/\${RealUserName}/.activate_psd
		fi

		sed -i "s/NODM_USER=\(.*\)/NODM_USER=\${RealUserName}/" /etc/default/nodm
		sed -i "s/NODM_ENABLED=\(.*\)/NODM_ENABLED=true/g" /etc/default/nodm
		echo "\n"
		echo "Now (re)starting desktop environment...\n"
		sleep 3
		service nodm stop
		sleep 1
		service nodm start
	;;
	esac

	db_stop
	exit 0
	EOF
	chmod 755 $destination/DEBIAN/postinst

	# add loading desktop splash service
	mkdir -p $destination/etc/systemd/system/
	cp $SRC/packages/blobs/desktop/desktop-splash/desktop-splash.service $destination/etc/systemd/system/desktop-splash.service

	# install optimized chromium configuration
	mkdir -p $destination/etc/armbian
	cp $SRC/packages/blobs/desktop/chromium.conf $destination/etc/armbian
	cp $SRC/packages/blobs/desktop/firefox.conf  $destination/etc/armbian

	# install default desktop settings
	mkdir -p $destination/etc/skel
	cp -R $SRC/packages/blobs/desktop/skel/. $destination/etc/skel

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
	display_alert "Building desktop package" "armbian-desktop-${RELEASE}_${REVISION}_all" "info"
	fakeroot dpkg-deb -b $destination ${destination}.deb >/dev/null
	mkdir -p ${DEST}/debs/${RELEASE}
	mv ${destination}.deb $DEST/debs/${RELEASE}
	# cleanup
	rm -rf $destination
}
