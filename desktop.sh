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
#--------------------------------------------------------------------------------------------------------------------------------
# Install desktop with HW acceleration
#--------------------------------------------------------------------------------------------------------------------------------
display_alert "Installing desktop" "XFCE" "info"

umount $DEST/cache/sdcard/tmp >/dev/null 2>&1
mount --bind $SRC/lib/bin/ $DEST/cache/sdcard/tmp

OFFICE_PACKETS="libreoffice-writer libreoffice-java-common"

# Debian Wheezy
if [[ $RELEASE == "wheezy" ]]; then
BASIC_PACKETS="xserver-xorg xserver-xorg-core xfonts-base xinit nodm x11-xserver-utils xfce4 mozo pluma wicd thunar-volman \
galculator iceweasel libgnome2-perl gcj-jre-headless gtk2-engines gtk2-engines-murrine gtk2-engines-pixbuf libgtk2.0-bin \
xfce4-screenshooter icedove radiotray mirage xterm lxtask"
# copy wallpapers and default desktop settings
d=$DEST/cache/sdcard/usr/share/xfce4/backdrops/
test -d "$d" || mkdir -p "$d" && cp $SRC/lib/bin/armbian*.jpg "$d"
#cp $SRC/lib/config/wheezy-desktop.tgz /tmp/kernel # start configuration
chroot $DEST/cache/sdcard /bin/bash -c "tar xfz /tmp/wheezy-desktop.tgz -C /root/"
fi

# Debian Jessie
if [[ $RELEASE == "jessie" ]]; then
BASIC_PACKETS="xserver-xorg xserver-xorg-core xfonts-base xinit nodm x11-xserver-utils xfce4 mozo pluma wicd thunar-volman \
galculator iceweasel libgnome2-perl gcj-jre-headless gtk2-engines gtk2-engines-murrine gtk2-engines-pixbuf libgtk2.0-bin \
$OFFICE_PACKETS xfce4-screenshooter icedove radiotray mirage xterm lxtask"
# copy wallpapers
d=$DEST/cache/sdcard/usr/share/backgrounds/xfce/
test -d "$d" || mkdir -p "$d" && cp $SRC/lib/bin/armbian*.jpg "$d"
#cp $SRC/lib/config/jessie-desktop.tgz /tmp/kernel # start configuration
chroot $DEST/cache/sdcard /bin/bash -c "tar xfz /tmp/jessie-desktop.tgz -C /root/"
fi

# Ubuntu trusty
if [[ $RELEASE == "trusty" ]]; then
BASIC_PACKETS="xserver-xorg xserver-xorg-core xfonts-base xinit nodm x11-xserver-utils xfce4 wicd thunar-volman galculator \
libgnome2-perl gcj-jre-headless gtk2-engines gtk2-engines-murrine gtk2-engines-pixbuf libgtk2.0-bin \
$OFFICE_PACKETS xfce4-screenshooter thunderbird firefox radiotray mirage gnome-icon-theme-full \
tango-icon-theme xterm lxtask gvfs-backends"
# copy wallpapers and default desktop settings
d=$DEST/cache/sdcard/usr/share/backgrounds/xfce/
test -d "$d" || mkdir -p "$d" && cp $SRC/lib/bin/armbian*.jpg "$d"
#cp $SRC/lib/config/trusty-desktop.tgz /tmp/kernel # start configuration
chroot $DEST/cache/sdcard /bin/bash -c "tar xfz /tmp/trusty-desktop.tgz -C /root/"
fi

# Install packets
i=0
j=1
declare -a PACKETS=($BASIC_PACKETS)
skupaj=${#PACKETS[@]}
while [[ $i -lt $skupaj ]]; do
procent=$(echo "scale=2;($j/$skupaj)*100"|bc)
		x=${PACKETS[$i]}	
		if [ "$(chroot $DEST/cache/sdcard /bin/bash -c "apt-get -qq -y install $x >/tmp/install.log 2>&1 || echo 'Installation failed'" | grep 'Installation failed')" != "" ]; then 
			echo -e "[\e[0;31m error \x1B[0m] Installation failed"
			tail $DEST/cache/sdcard/tmp/install.log
			exit
		fi
		printf '%.0f\n' $procent | dialog --gauge "Installing desktop" 7 50
		i=$[$i+1]
		j=$[$j+1]
done

# Install custom icons and theme
#cp $SRC/lib/bin/vibrancy-colors_2.4-trusty-Noobslab.com_all.deb /tmp/kernel
#cp $SRC/lib/bin/NumixHolo.zip /tmp/kernel
chroot $DEST/cache/sdcard /bin/bash -c "dpkg -i /tmp/vibrancy-colors_2.4-trusty-Noobslab.com_all.deb >/dev/null 2>&1"
chroot $DEST/cache/sdcard /bin/bash -c "unzip -qq /tmp/NumixHolo.zip -d /usr/share/themes"
# cleanup
chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y autoremove"
chroot $DEST/cache/sdcard /bin/bash -c "apt-get clean"

umount $DEST/cache/sdcard/tmp >/dev/null 2>&1

# fix for udoo
if [[ $BOARD != "udoo" ]]; then
	echo "[Settings]" > $DEST/cache/sdcard/etc/wicd/manager-settings.conf
	echo "wireless_interface = wlan0" >> $DEST/cache/sdcard/etc/wicd/manager-settings.conf
fi

# Enable desktop moode autostart without password
sed "s/NODM_ENABLED=\(.*\)/NODM_ENABLED=true/g" -i $DEST/cache/sdcard/etc/default/nodm
 
# Compile Turbo Frame buffer for sunxi
if [[ $LINUXCONFIG == *sunxi* && $BRANCH != "next" ]]; then
 chroot $DEST/cache/sdcard /bin/bash -c "debconf-apt-progress -- apt-get -y install xorg-dev xutils-dev x11proto-dri2-dev xutils-dev libdrm-dev libvdpau-dev"
 # quemu bug walkaround
 git clone https://github.com/ssvb/xf86-video-fbturbo.git $DEST/cache/sdcard/tmp/xf86-video-fbturbo
 chroot $DEST/cache/sdcard /bin/bash -c "cd /tmp/xf86-video-fbturbo && autoreconf -vi"
 chroot $DEST/cache/sdcard /bin/bash -c "cd /tmp/xf86-video-fbturbo && ./configure --prefix=/usr"
 chroot $DEST/cache/sdcard /bin/bash -c "cd /tmp/xf86-video-fbturbo && make && make install && cp xorg.conf /etc/X11/xorg.conf"
 # compile video acceleration
 git clone https://github.com/linux-sunxi/libvdpau-sunxi.git $DEST/cache/sdcard/tmp/libvdpau-sunxi
 chroot $DEST/cache/sdcard /bin/bash -c "cd /tmp/libvdpau-sunxi && make"
 d=$DEST/cache/sdcard/usr/lib/vdpau
 test -d "$d" || mkdir -p "$d" && cp $DEST/cache/sdcard/tmp/libvdpau-sunxi/libvdpau_sunxi.so.1 "$d"
 ln -s $d/libvdpau_sunxi.so $d/libvdpau_sunxi.so.1
 
 # That we can just play
 echo "export VDPAU_DRIVER=sunxi" >> $DEST/cache/sdcard/etc/profile
 # enable memory reservations
 sed "s/sunxi_ve_mem_reserve=0 sunxi_g2d_mem_reserve=0 sunxi_no_mali_mem_reserve sunxi_fb_mem_reserve=16 //g" -i $DEST/cache/sdcard/boot/boot.cmd
 mkimage -C none -A arm -T script -d $DEST/cache/sdcard/boot/boot.cmd $DEST/cache/sdcard/boot/boot.scr >> /dev/null 
 # clean deb cache
 chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y clean"	
fi

if [[ $LINUXCONFIG == *sunxi* ]]; then
# disable DPMS for sunxi because screen doesn't resume
cat >> $DEST/cache/sdcard/etc/X11/xorg.conf <<EOT
Section "Monitor"
        Identifier      "Monitor0"
        Option          "DPMS" "false"
EndSection
Section "ServerFlags"
    Option         "BlankTime" "0"
    Option         "StandbyTime" "0"
    Option         "SuspendTime" "0"
    Option         "OffTime" "0"
EndSection
EOT
fi
}
