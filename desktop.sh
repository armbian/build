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


install_desktop (){
#---------------------------------------------------------------------------------------------------------------------------------
# Install desktop with HW acceleration
#---------------------------------------------------------------------------------------------------------------------------------
display_alert "Installing desktop" "XFCE" "info"

umount $DEST/cache/sdcard/tmp >/dev/null 2>&1
mount --bind $SRC/lib/bin/ $DEST/cache/sdcard/tmp

# Debian Wheezy
if [[ $RELEASE == "wheezy" ]]; then
	# copy wallpapers and default desktop settings
	d=$DEST/cache/sdcard/usr/share/xfce4/backdrops/
	test -d "$d" || mkdir -p "$d" && cp $SRC/lib/bin/armbian*.jpg "$d"	
	chroot $DEST/cache/sdcard /bin/bash -c "tar xfz /tmp/wheezy-desktop.tgz -C /etc/skel/"
	chroot $DEST/cache/sdcard /bin/bash -c "tar xfz /tmp/wheezy-desktop.tgz -C /root/"
fi

# Debian Jessie
if [[ $RELEASE == "jessie" ]]; then
	# copy wallpapers and default desktop settings
	d=$DEST/cache/sdcard/usr/share/backgrounds/xfce/
	test -d "$d" || mkdir -p "$d" && cp $SRC/lib/bin/armbian*.jpg "$d"	
	chroot $DEST/cache/sdcard /bin/bash -c "tar xfz /tmp/jessie-desktop.tgz -C /etc/skel/"
	chroot $DEST/cache/sdcard /bin/bash -c "tar xfz /tmp/jessie-desktop.tgz -C /root/"
fi

# Ubuntu trusty
if [[ $RELEASE == "trusty" ]]; then
	# copy wallpapers and default desktop settings
	d=$DEST/cache/sdcard/usr/share/backgrounds/xfce/
	test -d "$d" || mkdir -p "$d" && cp $SRC/lib/bin/armbian*.jpg "$d"	
	chroot $DEST/cache/sdcard /bin/bash -c "tar xfz /tmp/trusty-desktop.tgz -C /etc/skel/"
	chroot $DEST/cache/sdcard /bin/bash -c "tar xfz /tmp/trusty-desktop.tgz -C /root/"
fi

# Install custom icons and theme
chroot $DEST/cache/sdcard /bin/bash -c "dpkg -i /tmp/vibrancy-colors_2.4-trusty-Noobslab.com_all.deb >/dev/null 2>&1"
chroot $DEST/cache/sdcard /bin/bash -c "unzip -qq /tmp/NumixHolo.zip -d /usr/share/themes"
# cleanup
chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y autoremove >/dev/null 2>&1"
chroot $DEST/cache/sdcard /bin/bash -c "apt-get clean >/dev/null 2>&1"

# unmount bind mount
umount $DEST/cache/sdcard/tmp >/dev/null 2>&1

# fix for udoo
if [[ $BOARD != "udoo" ]]; then
	echo "[Settings]" > $DEST/cache/sdcard/etc/wicd/manager-settings.conf
	echo "wireless_interface = wlan0" >> $DEST/cache/sdcard/etc/wicd/manager-settings.conf
fi

# Disable desktop mode autostart for now to enforce creation of normal user account
sed "s/NODM_ENABLED=\(.*\)/NODM_ENABLED=false/g" -i $DEST/cache/sdcard/etc/default/nodm
 
# Compile Turbo Frame buffer for sunxi
if [[ $LINUXFAMILY == *sun* && $BRANCH == "default" ]]; then

	grep "CONFIG_MALI is not set" $SOURCES/$LINUXSOURCEDIR/.config 2>&1 >/dev/null
	local error_num=$?
	grep "CONFIG_UMP is not set" $SOURCES/$LINUXSOURCEDIR/.config 2>&1 >/dev/null
	if [[ $? -eq 1 && $error_num -eq 1 ]]
	then
	error_num=0
	display_alert "Adding support for Mali - acceleration" "sunxi" "info"
	git clone -q https://github.com/WereCatf/armbian-debs.git $DEST/cache/sdcard/tmp/armbian-debs
	chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y install mesa-utils-extra 2>&1 >/dev/null"	
	chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y install libdri2-1 libdri2-dev 2>&1 >/dev/null"
	if [ $? -gt 0 ]; then
	chroot $DEST/cache/sdcard /bin/bash -c "cd /tmp/armbian-debs && dpkg -i libdri2-1_1.0-1_armhf.deb 2>&1 >/dev/null"
	error_num=$(($error_num+$?))
	fi
	if [ $error_num -gt 0 ]; then display_alert "Installation failed" "Mali - libdri2-1" "err"; exit 1
	else
	chroot $DEST/cache/sdcard /bin/bash -c "cd /tmp/armbian-debs && dpkg -i libump_3.0-0sunxi1_armhf.deb libump-dev_3.0-0sunxi1_armhf.deb 2>&1 >/dev/null"
	error_num=$(($error_num+$?))
	if [ $error_num -gt 0 ]; then display_alert "Installation failed" "Mali - libump" "err"; exit 1
	else
	chroot $DEST/cache/sdcard /bin/bash -c "cd /tmp/armbian-debs && dpkg -i sunxi-mali-r3p0_4.0.0.0_armhf.deb 2>&1 >/dev/null"
	error_num=$(($error_num+$?))
	chroot $DEST/cache/sdcard /bin/bash -c "ldconfig"
	if [ $error_num -gt 0 ]; then display_alert "Installation failed" "Mali r3p0" "err"; exit 1;fi
	fi
	fi
	fi

	display_alert "Compiling FB Turbo" "sunxi" "info"

	error_num=0
	
	# quemu bug walkaround
	git clone -q https://github.com/ssvb/xf86-video-fbturbo.git $DEST/cache/sdcard/tmp/xf86-video-fbturbo
	chroot $DEST/cache/sdcard /bin/bash -c "cd /tmp/xf86-video-fbturbo && autoreconf -vi >/dev/null 2>&1"
	error_num=$(($error_num+$?))
	chroot $DEST/cache/sdcard /bin/bash -c "cd /tmp/xf86-video-fbturbo && ./configure --prefix=/usr >/dev/null 2>&1"
	error_num=$(($error_num+$?))
	chroot $DEST/cache/sdcard /bin/bash -c "cd /tmp/xf86-video-fbturbo && make $CTHREADS && make install >/dev/null 2>&1"	
	error_num=$(($error_num+$?))
 
	# use Armbian prepared config
	cp $SRC/lib/config/xorg.conf.sunxi $DEST/cache/sdcard/etc/X11/xorg.conf
 
	# compile video acceleration
	git clone -q https://github.com/linux-sunxi/libvdpau-sunxi.git $DEST/cache/sdcard/tmp/libvdpau-sunxi 
	
	# with temporaly fix
	chroot $DEST/cache/sdcard /bin/bash -c "cd /tmp/libvdpau-sunxi; git checkout 906c36ed45ceb53fecd5fc72e821c11849eeb1a3; make $CTHREADS" >/dev/null 2>&1	
	error_num=$(($error_num+$?))	
	
	d=$DEST/cache/sdcard/usr/lib/arm-linux-gnueabihf/vdpau
	test -d "$d" || mkdir -p "$d" && cp $DEST/cache/sdcard/tmp/libvdpau-sunxi/libvdpau_sunxi.so.1 "$d"
	ln -s $d/libvdpau_sunxi.so.1 $d/libvdpau_sunxi.so

	# That we can just play
	echo "export VDPAU_DRIVER=sunxi" >> $DEST/cache/sdcard/etc/profile
	
	# enable memory reservations
	sed "s/sunxi_ve_mem_reserve=0 sunxi_g2d_mem_reserve=0 sunxi_no_mali_mem_reserve sunxi_fb_mem_reserve=16 //g" -i $DEST/cache/sdcard/boot/boot.cmd
	mkimage -C none -A arm -T script -d $DEST/cache/sdcard/boot/boot.cmd $DEST/cache/sdcard/boot/boot.scr >> /dev/null 
	
	# clean deb cache
	chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y clean >/dev/null 2>&1"	
	
	# error chech
	if [ $error_num -gt 0 ]; then display_alert "Compiling failed" "FB Turbo" "err"; exit 1; fi
fi
}
