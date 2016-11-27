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

	mkdir -p $CACHEDIR/$SDCARD/tmp/bin
	mount --bind $SRC/lib/bin/ $CACHEDIR/$SDCARD/tmp/bin

	# install default desktop settings
	chroot $CACHEDIR/$SDCARD /bin/bash -c "tar xfz /tmp/bin/$RELEASE-desktop.tgz -C /etc/skel/"
	chroot $CACHEDIR/$SDCARD /bin/bash -c "tar xfz /tmp/bin/$RELEASE-desktop.tgz -C /root/"

	# install wallpapers
	case $RELEASE in
		wheezy)
		d=$CACHEDIR/$SDCARD/usr/share/xfce4/backdrops/
		test -d "$d" || mkdir -p "$d" && cp $SRC/lib/bin/armbian*.jpg "$d"
		;;

		jessie|xenial)
		d=$CACHEDIR/$SDCARD/usr/share/backgrounds/xfce/
		test -d "$d" || mkdir -p "$d" && cp $SRC/lib/bin/armbian*.jpg "$d"
		mkdir -p $CACHEDIR/$SDCARD/etc/polkit-1/localauthority/50-local.d
		cp $SRC/lib/config/polkit-jessie/*.pkla $CACHEDIR/$SDCARD/etc/polkit-1/localauthority/50-local.d/
		;;

		trusty)
		d=$CACHEDIR/$SDCARD/usr/share/backgrounds/xfce/
		test -d "$d" || mkdir -p "$d" && cp $SRC/lib/bin/armbian*.jpg "$d"
		;;
	esac

	# Install custom icons and theme
	chroot $CACHEDIR/$SDCARD /bin/bash -c "dpkg -i /tmp/bin/vibrancy-colors_2.4-trusty-Noobslab.com_all.deb >/dev/null 2>&1"
	chroot $CACHEDIR/$SDCARD /bin/bash -c "unzip -qq /tmp/bin/NumixHolo.zip -d /usr/share/themes"

	# Enable network manager
	if [[ -f ${CACHEDIR}/$SDCARD/etc/NetworkManager/NetworkManager.conf ]]; then
		sed "s/managed=\(.*\)/managed=true/g" -i $CACHEDIR/$SDCARD/etc/NetworkManager/NetworkManager.conf
		# Disable dns management withing NM
		sed "s/\[main\]/\[main\]\ndns=none/g" -i $CACHEDIR/$SDCARD/etc/NetworkManager/NetworkManager.conf
		printf '[keyfile]\nunmanaged-devices=interface-name:p2p0\n' >> $CACHEDIR/$SDCARD/etc/NetworkManager/NetworkManager.conf
	fi

	# Disable Pulseaudio timer scheduling which does not work with sndhdmi driver
	if [[ -f ${CACHEDIR}/$SDCARD/etc/pulse/default.pa ]]; then
		sed "s/load-module module-udev-detect$/& tsched=0/g" -i  $CACHEDIR/$SDCARD/etc/pulse/default.pa
	fi

	# Disable desktop mode autostart for now to enforce creation of normal user account
	sed "s/NODM_ENABLED=\(.*\)/NODM_ENABLED=false/g" -i $CACHEDIR/$SDCARD/etc/default/nodm

	# Compile Turbo Frame buffer for sunxi
	if [[ $LINUXFAMILY == sun* && $BRANCH == default ]]; then

		if [[ $RELEASE == jessie || $RELEASE == xenial ]]; then
			# Disable compositing by default
			sed 's/name="use_compositing" type="bool" value="true"/name="use_compositing" type="bool" value="false"/' -i $CACHEDIR/$SDCARD/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
			sed 's/name="use_compositing" type="bool" value="true"/name="use_compositing" type="bool" value="false"/' -i $CACHEDIR/$SDCARD/root/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
		fi

		# Set default audio-output to HDMI for desktop-images
		cat <<-EOF >> $CACHEDIR/$SDCARD/etc/asound.conf
		pcm.!default {
		    type hw
		    card 1
		}

		ctl.!default {
		    type hw
		    card 1
		}
		EOF

		# enable memory reservations
		if [[ -f $CACHEDIR/$SDCARD/boot/armbianEnv.txt ]]; then
			echo "disp_mem_reserves=on" >> $CACHEDIR/$SDCARD/boot/armbianEnv.txt
		else
			sed "s/sunxi_ve_mem_reserve=0 sunxi_g2d_mem_reserve=0 sunxi_fb_mem_reserve=16 //g" -i $CACHEDIR/$SDCARD/boot/boot.cmd
		fi
	fi

	umount $CACHEDIR/$SDCARD/tmp/bin && rm -rf $CACHEDIR/$SDCARD/tmp/bin
}
