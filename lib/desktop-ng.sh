# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

install_desktop ()
{
	display_alert "Creating desktop package" "XFCE" "info"

	# temporally. move to configuration.sh once this file gets in action
	PACKAGE_LIST_DESKTOP="$PACKAGE_LIST_DESKTOP numix-icon-theme"

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

		# fix for gksu in Xenial
		touch /home/\${RealUserName}/.Xauthority
		chown \${RealUserName}:\${RealUserName} /home/\${RealUserName}/.Xauthority

		# set up profile sync daemon on desktop systems
		which psd >/dev/null 2>&1
		if [ \$? -eq 0 ]; then
			echo "\${RealUserName} ALL=(ALL) NOPASSWD: /usr/bin/psd-overlay-helper" >> /etc/sudoers
			touch /home/\${RealUserName}/.activate_psd
			chown \${RealUserName}:\${RealUserName} /home/\${RealUserName}/.activate_psd
		fi

		sed -i "s/NODM_USER=\(.*\)/NODM_USER=\${RealUserName}/" /etc/default/nodm
		sed -i "s/NODM_ENABLED=\(.*\)/NODM_ENABLED=true/g" /etc/default/nodm
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
	mkdir -p $destination/etc/chromium-browser $destination/etc/chromium.d
	cp $SRC/packages/blobs/desktop/chromium.conf $destination/etc/chromium-browser/default
	cp $SRC/packages/blobs/desktop/chromium.conf $destination/etc/chromium.d/chromium.conf

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

	# Disable desktop mode autostart for now to enforce creation of normal user account
	[[ -f $SDCARD/etc/default/nodm ]] && sed "s/NODM_ENABLED=\(.*\)/NODM_ENABLED=false/g" -i $SDCARD/etc/default/nodm
	[[ -d $SDCARD/etc/lightdm ]] && chroot $SDCARD /bin/bash -c "systemctl --no-reload disable lightdm.service >/dev/null 2>&1"

	# create board DEB file
	display_alert "Building Armbian desktop package" "$CHOSEN_ROOTFS" "info"
	fakeroot dpkg-deb -b $destination ${destination}.deb >/dev/null
	mkdir -p $DEST/debs/
	mv ${destination}.deb $DEST/debs/
	# cleanup
	rm -rf $destination
}
