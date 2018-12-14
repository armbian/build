# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# Functions:
# mount_chroot
# umount_chroot
# unmount_on_exit
# check_loop_device
# install_external_applications
# write_uboot
# customize_image
# install_deb_chroot
# desktop_postinstall


# mount_chroot <target>
#
# helper to reduce code duplication
#
mount_chroot()
{
	local target=$1
	mount -t proc chproc $target/proc
	mount -t sysfs chsys $target/sys
	mount -t devtmpfs chdev $target/dev || mount --bind /dev $target/dev
	mount -t devpts chpts $target/dev/pts
} #############################################################################

# umount_chroot <target>
#
# helper to reduce code duplication
#
umount_chroot()
{
	local target=$1
	umount -l $target/dev/pts >/dev/null 2>&1
	umount -l $target/dev >/dev/null 2>&1
	umount -l $target/proc >/dev/null 2>&1
	umount -l $target/sys >/dev/null 2>&1
} #############################################################################

# unmount_on_exit
#
unmount_on_exit()
{
	trap - INT TERM EXIT
	umount_chroot "$SDCARD/"
	umount -l $SDCARD/tmp >/dev/null 2>&1
	umount -l $SDCARD >/dev/null 2>&1
	umount -l $MOUNT/boot >/dev/null 2>&1
	umount -l $MOUNT >/dev/null 2>&1
	[[ $CRYPTROOT_ENABLE == yes ]] && cryptsetup luksClose $ROOT_MAPPER
	losetup -d $LOOP >/dev/null 2>&1
	rm -rf --one-file-system $SDCARD
	exit_with_error "debootstrap-ng was interrupted"
} #############################################################################

# check_loop_device <device_node>
#
check_loop_device()
{
	local device=$1
	if [[ ! -b $device ]]; then
		if [[ $CONTAINER_COMPAT == yes && -b /tmp/$device ]]; then
			display_alert "Creating device node" "$device"
			mknod -m0660 $device b 0x$(stat -c '%t' "/tmp/$device") 0x$(stat -c '%T' "/tmp/$device")
		else
			exit_with_error "Device node $device does not exist"
		fi
	fi
} #############################################################################

# write_uboot <loopdev>
#
# writes u-boot to loop device
# Parameters:
# loopdev: loop device with mounted rootfs image
#
write_uboot()
{
if [[ $ADD_UBOOT == yes ]]; then
	local loop=$1
	display_alert "Writing U-boot bootloader" "$loop" "info"
	mkdir -p /tmp/u-boot/
	dpkg -x ${DEST}/debs/${CHOSEN_UBOOT}_${REVISION}_${ARCH}.deb /tmp/u-boot/
	write_uboot_platform "/tmp/u-boot/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}" "$loop"
	[[ $? -ne 0 ]] && exit_with_error "U-boot bootloader failed to install" "@host"
	rm -r /tmp/u-boot/
	sync
fi
} #############################################################################

customize_image()
{
	# for users that need to prepare files at host
	[[ -f $SRC/userpatches/customize-image-host.sh ]] && source $SRC/userpatches/customize-image-host.sh
	cp $SRC/userpatches/customize-image.sh $SDCARD/tmp/customize-image.sh
	chmod +x $SDCARD/tmp/customize-image.sh
	mkdir -p $SDCARD/tmp/overlay
	# util-linux >= 2.27 required
	mount -o bind,ro $SRC/userpatches/overlay $SDCARD/tmp/overlay
	display_alert "Calling image customization script" "customize-image.sh" "info"
	chroot $SDCARD /bin/bash -c "/tmp/customize-image.sh $RELEASE $LINUXFAMILY $BOARD $BUILD_DESKTOP"
	CUSTOMIZE_IMAGE_RC=$?
	umount $SDCARD/tmp/overlay
	mountpoint -q $SDCARD/tmp/overlay || rm -r $SDCARD/tmp/overlay
	if [[ $CUSTOMIZE_IMAGE_RC != 0 ]]; then
		exit_with_error "customize-image.sh exited with error (rc: $CUSTOMIZE_IMAGE_RC)"
	fi
} #############################################################################

install_deb_chroot()
{
	local package=$1
	local name=$(basename $package)
	cp $package $SDCARD/root/$name
	chroot $SDCARD /bin/bash -c "dpkg -i /root/$name" >> $DEST/debug/install.log 2>&1
	if [[ $? == 0 ]]; then display_alert "Installed" "$name" "info"; else display_alert "Installed" "$name" "err"; fi
	rm -f $SDCARD/root/$name
}

desktop_postinstall ()
{
	# stage: install display manager
	display_alert "Upgrading all packages" "Preparing" "info"
	chroot $SDCARD /bin/bash -c "apt-get -y -qq update; apt-get -y upgrade" >> $DEST/debug/install.log 2>&1
	display_alert "Installing" "display manager: $DISPLAY_MANAGER" "info"
	chroot $SDCARD /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=\"--force-confold\" -y -qq install $PACKAGE_LIST_DISPLAY_MANAGER" >> $DEST/debug/install.log 2>&1
	[[ -f $SDCARD/etc/default/nodm ]] && sed "s/NODM_ENABLED=\(.*\)/NODM_ENABLED=false/g" -i $SDCARD/etc/default/nodm
	[[ -d $SDCARD/etc/lightdm ]] && chroot $SDCARD /bin/bash -c "systemctl --no-reload disable lightdm.service >/dev/null 2>&1"

	# Compile Turbo Frame buffer for sunxi
	if [[ $LINUXFAMILY == sun* && $BRANCH == default ]]; then
		sed 's/name="use_compositing" type="bool" value="true"/name="use_compositing" type="bool" value="false"/' -i $SDCARD/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml

		# enable memory reservations
		echo "disp_mem_reserves=on" >> $SDCARD/boot/armbianEnv.txt
		echo "extraargs=cma=96M" >> $SDCARD/boot/armbianEnv.txt
	fi
}
