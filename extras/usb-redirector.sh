# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of tool chain https://github.com/igorpecovnik/lib
#

# USB redirector tools http://www.incentivespro.com

install_usb_redirector()
{
	IFS='.' read -a array <<< "$VER"
	# Current USB redirector is broken for old kernels
	cd $SOURCES
	if (( "${array[0]}" == "4" )) && (( "${array[1]}" >= "1" )); then
		wget -q http://www.incentivespro.com/usb-redirector-linux-arm-eabi.tar.gz
	else
		cp $SRC/lib/bin/usb-redirector-old.tgz usb-redirector-linux-arm-eabi.tar.gz
	fi
	
	tar xfz usb-redirector-linux-arm-eabi.tar.gz
	rm usb-redirector-linux-arm-eabi.tar.gz
	cd $SOURCES/usb-redirector-linux-arm-eabi/files/modules/src/tusbd
	# patch to work with newer kernels
	sed -e "s/f_dentry/f_path.dentry/g" -i usbdcdev.c
	# Remove inlining for now, as function body must have been defined in utils.h:
	sed -e 's/inline int/int/g' -i utils.h utils.c
	if [[ $ARCH == *64* ]]; then ARCHITECTURE=arm64; else ARCHITECTURE=arm; fi
	make -j1 ARCH=$ARCHITECTURE CROSS_COMPILE="$CCACHE $KERNEL_COMPILER" KERNELDIR=$SOURCES/$LINUXSOURCEDIR/ >> $DEST/debug/install.log 2>&1
	# configure USB redirector
	sed -e 's/%INSTALLDIR_TAG%/\/usr\/local/g' $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd > $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd1
	sed -e 's/%PIDFILE_TAG%/\/var\/run\/usbsrvd.pid/g' $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd1 > $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd
	sed -e 's/%STUBNAME_TAG%/tusbd/g' $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd > $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd1
	sed -e 's/%DAEMONNAME_TAG%/usbsrvd/g' $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd1 > $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd
	chmod +x $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd
	# copy to root
	cp $SOURCES/usb-redirector-linux-arm-eabi/files/usb* $CACHEDIR/sdcard/usr/local/bin/
	cp $SOURCES/usb-redirector-linux-arm-eabi/files/modules/src/tusbd/tusbd.ko $CACHEDIR/sdcard/usr/local/bin/
	cp $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd $CACHEDIR/sdcard/etc/init.d/
	# not started by default ----- update.rc rc.usbsrvd defaults
	# chroot $CACHEDIR/sdcard /bin/bash -c "update-rc.d rc.usbsrvd defaults
}

display_alert "Installing additional application" "USB redirector" "info"
install_usb_redirector
