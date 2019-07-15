#!/bin/bash
#
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


# mount_chroot <target>
#
# helper to reduce code duplication
#
mount_chroot()
{
	local target=$1
	mount -t proc chproc "${target}"/proc
	mount -t sysfs chsys "${target}"/sys
	mount -t devtmpfs chdev "${target}"/dev || mount --bind /dev "${target}"/dev
	mount -t devpts chpts "${target}"/dev/pts
} #############################################################################

# umount_chroot <target>
#
# helper to reduce code duplication
#
umount_chroot()
{
	local target=$1
	umount -l "${target}"/dev/pts >/dev/null 2>&1
	umount -l "${target}"/dev >/dev/null 2>&1
	umount -l "${target}"/proc >/dev/null 2>&1
	umount -l "${target}"/sys >/dev/null 2>&1
} #############################################################################

# unmount_on_exit
#
unmount_on_exit()
{
	trap - INT TERM EXIT
	umount_chroot "${SDCARD}/"
	umount -l "${SDCARD}"/tmp >/dev/null 2>&1
	umount -l "${SDCARD}" >/dev/null 2>&1
	umount -l "${MOUNT}"/boot >/dev/null 2>&1
	umount -l "${MOUNT}" >/dev/null 2>&1
	[[ $CRYPTROOT_ENABLE == yes ]] && cryptsetup luksClose "${ROOT_MAPPER}"
	losetup -d "${LOOP}" >/dev/null 2>&1
	rm -rf --one-file-system "${SDCARD}"
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
			mknod -m0660 "${device}" b "0x$(stat -c '%t' "/tmp/$device")" "0x$(stat -c '%T' "/tmp/$device")"
		else
			exit_with_error "Device node $device does not exist"
		fi
	fi
} #############################################################################

install_external_applications()
{
	display_alert "Installing extra applications and drivers" "" "info"

	for plugin in "${SRC}"/packages/extras/*.sh; do
		source "${plugin}"
	done
}  #############################################################################

# write_uboot <loopdev>
#
# writes u-boot to loop device
# Parameters:
# loopdev: loop device with mounted rootfs image
#
write_uboot()
{
	local loop=$1
	display_alert "Writing U-boot bootloader" "$loop" "info"
	mkdir -p /tmp/u-boot/
	dpkg -x "${DEST}/debs/${CHOSEN_UBOOT}_${REVISION}_${ARCH}.deb" /tmp/u-boot/
	write_uboot_platform "/tmp/u-boot/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}" "$loop"
	[[ $? -ne 0 ]] && exit_with_error "U-boot bootloader failed to install" "@host"
	rm -r /tmp/u-boot/
	sync
} #############################################################################

customize_image()
{
	# for users that need to prepare files at host
	[[ -f $SRC/userpatches/customize-image-host.sh ]] && source "${SRC}"/userpatches/customize-image-host.sh
	cp "${SRC}"/userpatches/customize-image.sh "${SDCARD}"/tmp/customize-image.sh
	chmod +x "${SDCARD}"/tmp/customize-image.sh
	mkdir -p "${SDCARD}"/tmp/overlay
	# util-linux >= 2.27 required
	mount -o bind,ro "${SRC}"/userpatches/overlay "${SDCARD}"/tmp/overlay
	display_alert "Calling image customization script" "customize-image.sh" "info"
	chroot "${SDCARD}" /bin/bash -c "/tmp/customize-image.sh $RELEASE $LINUXFAMILY $BOARD $BUILD_DESKTOP"
	CUSTOMIZE_IMAGE_RC=$?
	umount "${SDCARD}"/tmp/overlay
	mountpoint -q "${SDCARD}"/tmp/overlay || rm -r "${SDCARD}"/tmp/overlay
	if [[ $CUSTOMIZE_IMAGE_RC != 0 ]]; then
		exit_with_error "customize-image.sh exited with error (rc: $CUSTOMIZE_IMAGE_RC)"
	fi
} #############################################################################

install_deb_chroot()
{
	local package=$1
	local name
	name=$(basename "${package}")
	cp "${package}" "${SDCARD}/root/${name}"
	display_alert "Installing" "$name"
	[[ $NO_APT_CACHER != yes ]] && local apt_extra="-o Acquire::http::Proxy=\"http://${APT_PROXY_ADDR:-localhost:3142}\" -o Acquire::http::Proxy::localhost=\"DIRECT\""
	LC_ALL=C LANG=C chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -yqq \
		$apt_extra --no-install-recommends install ./root/$name" >> "${DEST}"/debug/install.log 2>&1

	rm -f "${SDCARD}/root/${name}"
}
