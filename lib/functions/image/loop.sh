# check_loop_device <device_node>
#
function check_loop_device() {
	do_with_retries 5 check_loop_device_internal "${@}" || {
		exit_with_error "Device node ${device} does not exist after 5 tries."
	}
	return 0 # shortcircuit above
}

function check_loop_device_internal() {
	local device=$1
	display_alert "Checking look device" "${device}" "debug"
	if [[ ! -b $device ]]; then
		if [[ $CONTAINER_COMPAT == yes && -b /tmp/$device ]]; then
			display_alert "Creating device node" "$device"
			mknod -m0660 "${device}" b "0x$(stat -c '%t' "/tmp/$device")" "0x$(stat -c '%T' "/tmp/$device")"
			return 1 # fail, it will be retried, and should exist on next retry.
		else
			display_alert "Device node does not exist yet" "$device" "debug"
			return 1
		fi
	fi
	return 0
}

#
# Copyright (c) 2013-2021 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# write_uboot <loopdev>
#
write_uboot_to_loop_image() {

	local loop=$1 revision
	display_alert "Preparing u-boot bootloader" "$loop" "info"
	TEMP_DIR=$(mktemp -d) # set-e is in effect. no need to exit on errors explicitly
	chmod 700 ${TEMP_DIR}
	revision=${REVISION}
	if [[ -n $UBOOT_REPO_VERSION ]]; then
		revision=${UBOOT_REPO_VERSION}
		run_host_command_logged dpkg -x "${DEB_STORAGE}/linux-u-boot-${BOARD}-${BRANCH}_${revision}_${ARCH}.deb" ${TEMP_DIR}/
	else
		run_host_command_logged dpkg -x "${DEB_STORAGE}/${CHOSEN_UBOOT}_${revision}_${ARCH}.deb" ${TEMP_DIR}/
	fi

	if [[ ! -f "${TEMP_DIR}/usr/lib/u-boot/platform_install.sh" ]]; then
		exit_with_error "Missing ${TEMP_DIR}/usr/lib/u-boot/platform_install.sh"
	fi

	display_alert "Sourcing u-boot install functions" "$loop" "info"
	source ${TEMP_DIR}/usr/lib/u-boot/platform_install.sh
	set -e # make sure, we just included something that might disable it

	display_alert "Writing u-boot bootloader" "$loop" "info"
	write_uboot_platform "${TEMP_DIR}${DIR}" "$loop" # @TODO: rpardini: what is ${DIR} ?

	export UBOOT_CHROOT_DIR="${TEMP_DIR}${DIR}"

	call_extension_method "post_write_uboot_platform" <<- 'POST_WRITE_UBOOT_PLATFORM'
		*allow custom writing of uboot -- only during image build*
		Called after `write_uboot_platform()`.
		It receives `UBOOT_CHROOT_DIR` with the full path to the u-boot dir in the chroot.
		Important: this is only called inside the build system.
		Consider that `write_uboot_platform()` is also called board-side, when updating uboot, eg: nand-sata-install.
	POST_WRITE_UBOOT_PLATFORM

	#rm -rf ${TEMP_DIR}

	return 0
}
