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

	mkdir -p $CACHEDIR/sdcard/tmp/bin
	mount --bind $SRC/lib/bin/ $CACHEDIR/sdcard/tmp/bin

	# install default desktop settings
	chroot $CACHEDIR/sdcard /bin/bash -c "tar xfz /tmp/bin/$RELEASE-desktop.tgz -C /etc/skel/"
	chroot $CACHEDIR/sdcard /bin/bash -c "tar xfz /tmp/bin/$RELEASE-desktop.tgz -C /root/"

	# install wallpapers
	case $RELEASE in
		wheezy)
		d=$CACHEDIR/sdcard/usr/share/xfce4/backdrops/
		test -d "$d" || mkdir -p "$d" && cp $SRC/lib/bin/armbian*.jpg "$d"
		;;

		jessie|xenial)
		d=$CACHEDIR/sdcard/usr/share/backgrounds/xfce/
		test -d "$d" || mkdir -p "$d" && cp $SRC/lib/bin/armbian*.jpg "$d"
		mkdir -p $CACHEDIR/sdcard/etc/polkit-1/localauthority/50-local.d
		cp $SRC/lib/config/polkit-jessie/*.pkla $CACHEDIR/sdcard/etc/polkit-1/localauthority/50-local.d/
		;;

		trusty)
		d=$CACHEDIR/sdcard/usr/share/backgrounds/xfce/
		test -d "$d" || mkdir -p "$d" && cp $SRC/lib/bin/armbian*.jpg "$d"
		;;
	esac

	# Install custom icons and theme
	chroot $CACHEDIR/sdcard /bin/bash -c "dpkg -i /tmp/bin/vibrancy-colors_2.4-trusty-Noobslab.com_all.deb >/dev/null 2>&1"
	chroot $CACHEDIR/sdcard /bin/bash -c "unzip -qq /tmp/bin/NumixHolo.zip -d /usr/share/themes"

	# Enable network manager
	if [[ -f ${CACHEDIR}/sdcard/etc/NetworkManager/NetworkManager.conf ]]; then
		sed "s/managed=\(.*\)/managed=true/g" -i $CACHEDIR/sdcard/etc/NetworkManager/NetworkManager.conf
		# Disable dns management withing NM
		sed "s/\[main\]/\[main\]\ndns=none/g" -i $CACHEDIR/sdcard/etc/NetworkManager/NetworkManager.conf
		printf '[keyfile]\nunmanaged-devices=interface-name:p2p0\n' >> $CACHEDIR/sdcard/etc/NetworkManager/NetworkManager.conf
	fi

	# Disable Pulseaudio timer scheduling which does not work with sndhdmi driver
	if [[ -f ${CACHEDIR}/sdcard/etc/pulse/default.pa ]]; then
		sed "s/load-module module-udev-detect$/& tsched=0/g" -i  $CACHEDIR/sdcard/etc/pulse/default.pa
	fi

	# Disable desktop mode autostart for now to enforce creation of normal user account
	sed "s/NODM_ENABLED=\(.*\)/NODM_ENABLED=false/g" -i $CACHEDIR/sdcard/etc/default/nodm

	# Compile Turbo Frame buffer for sunxi
	if [[ $LINUXFAMILY == sun* && $BRANCH == default ]]; then

		if [[ $RELEASE == jessie ]]; then
			# Disable compositing by default
			sed 's/name="use_compositing" type="bool" value="true"/name="use_compositing" type="bool" value="false"/' -i $CACHEDIR/sdcard/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
			sed 's/name="use_compositing" type="bool" value="true"/name="use_compositing" type="bool" value="false"/' -i $CACHEDIR/sdcard/root/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
		fi

		# Set default audio-output to HDMI for desktop-images
		cat <<-EOF >> $CACHEDIR/sdcard/etc/asound.conf
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
		sed "s/sunxi_ve_mem_reserve=0 sunxi_g2d_mem_reserve=0 sunxi_fb_mem_reserve=16 //g" -i $CACHEDIR/sdcard/boot/boot.cmd
		mkimage -C none -A arm -T script -d $CACHEDIR/sdcard/boot/boot.cmd $CACHEDIR/sdcard/boot/boot.scr >> /dev/null
	fi

	umount $CACHEDIR/sdcard/tmp/bin && rm -rf $CACHEDIR/sdcard/tmp/bin
}
