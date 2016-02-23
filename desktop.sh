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
	chroot $DEST/cache/sdcard /bin/bash -c "tar xfz /tmp/wheezy-desktop.tgz -C /root/"
fi

# Debian Jessie
if [[ $RELEASE == "jessie" ]]; then
	# copy wallpapers and default desktop settings
	d=$DEST/cache/sdcard/usr/share/backgrounds/xfce/
	test -d "$d" || mkdir -p "$d" && cp $SRC/lib/bin/armbian*.jpg "$d"	
	chroot $DEST/cache/sdcard /bin/bash -c "tar xfz /tmp/jessie-desktop.tgz -C /root/"
fi

# Ubuntu trusty
if [[ $RELEASE == "trusty" ]]; then
	# copy wallpapers and default desktop settings
	d=$DEST/cache/sdcard/usr/share/backgrounds/xfce/
	test -d "$d" || mkdir -p "$d" && cp $SRC/lib/bin/armbian*.jpg "$d"	
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

# Enable desktop moode autostart without password
sed "s/NODM_ENABLED=\(.*\)/NODM_ENABLED=true/g" -i $DEST/cache/sdcard/etc/default/nodm
 
# Compile Turbo Frame buffer for sunxi
if [[ $LINUXFAMILY == *sun* && $BRANCH == "default" ]]; then

	grep "CONFIG_MALI is not set" $SOURCES/$LINUXSOURCEDIR/.config 2>&1 >/dev/null
	local error_num=$?
	grep "CONFIG_UMP is not set" $SOURCES/$LINUXSOURCEDIR/.config 2>&1 >/dev/null
	if [[ $? -eq 1 || $error_num -eq 1 ]]
	then
	error_num=0
	display_alert "Compiling support for Mali - acceleration" "sunxi" "info"
	chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y install libx11-dev libxext-dev libdrm-dev x11proto-dri2-dev libxfixes-dev 2>&1 >/dev/null"
	chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y install libdri2-dev 2>&1 >/dev/null"
	if [ $? -gt 0 ]; then
	git clone -q https://github.com/robclark/libdri2 $DEST/cache/sdcard/tmp/libdri2
	chroot $DEST/cache/sdcard /bin/bash -c "cd /tmp/libdri2 && ./autogen.sh 2>&1 >/dev/null"
	error_num=$(($error_num+$?))
	chroot $DEST/cache/sdcard /bin/bash -c "cd /tmp/libdri2 && ./configure --prefix=/usr 2>&1 >/dev/null"
	error_num=$(($error_num+$?))
	chroot $DEST/cache/sdcard /bin/bash -c "cd /tmp/libdri2 && make -s $CTHREADS && make -s install && ldconfig 2>&1 >/dev/null"
	error_num=$(($error_num+$?))
	fi
	if [ $error_num -gt 0 ]; then display_alert "Compiling failed" "Mali - acceleration" "err"; exit 1
	else
	chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y install git build-essential autoconf libtool 2>&1 >/dev/null"
	git clone -q https://github.com/linux-sunxi/libump.git $DEST/cache/sdcard/tmp/libump
	chroot $DEST/cache/sdcard /bin/bash -c "cd /tmp/libump && autoreconf -i 2>&1 >/dev/null"
	error_num=$(($error_num+$?))
	chroot $DEST/cache/sdcard /bin/bash -c "cd /tmp/libump && ./configure --prefix=/usr 2>&1 >/dev/null"
	error_num=$(($error_num+$?))
	chroot $DEST/cache/sdcard /bin/bash -c "cd /tmp/libump && make -s $CTHREADS && make -s install 2>&1 >/dev/null"
	error_num=$(($error_num+$?))
	if [ $error_num -gt 0 ]; then display_alert "Compiling failed" "Mali - acceleration" "err"; exit 1
	else
	chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y install git build-essential autoconf automake xutils-dev 2>&1 >/dev/null"
	git clone -q --recursive https://github.com/WhiteWind/sunxi-mali $DEST/cache/sdcard/tmp/sunxi-mali
	sed 's/(prefix)lib\//(prefix)lib\/mali\//' -i $DEST/cache/sdcard/tmp/sunxi-mali/Makefile.setup
	chroot $DEST/cache/sdcard /bin/bash -c "cd /tmp/sunxi-mali && ABI=armhf VERSION=r3p0 EGL_TYPE=x11 make -s config 2>&1 >/dev/null"
	error_num=$(($error_num+$?))
	chroot $DEST/cache/sdcard /bin/bash -c "cd /tmp/sunxi-mali && make -s -f Makefile.pc 2>&1 >/dev/null"
	error_num=$(($error_num+$?))
	chroot $DEST/cache/sdcard /bin/bash -c "cd /tmp/sunxi-mali && make -s install 2>&1 >/dev/null"
	error_num=$(($error_num+$?))
	mkdir -p $DEST/cache/sdcard/usr/lib/pkgconfig
	mv $DEST/cache/sdcard/usr/lib/mali/pkgconfig/* $DEST/cache/sdcard/usr/lib/pkgconfig/
	mkdir -p $DEST/cache/sdcard/etc/udev/rules.d
	cp $SRC/lib/config/sunxi-udev/* $DEST/cache/sdcard/etc/udev/rules.d/
	sed 's/# Multiarch support/\/usr\/lib\/mali\n# Multiarch support/' -i $DEST/cache/sdcard/etc/ld.so.conf.d/arm-linux-gnueabihf.conf
	chroot $DEST/cache/sdcard /bin/bash -c "ldconfig"
	if [ $error_num -gt 0 ]; then display_alert "Compiling failed" "Mali - acceleration" "err"; exit 1;fi
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
