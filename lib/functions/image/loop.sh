#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

#!/usr/bin/env bash
# check_loop_device <device_node>
#
function check_loop_device() {
	do_with_retries 5 check_loop_device_internal "${@}" || {
		exit_with_error "Device node ${device} does not exist after 5 tries."
	}
	return 0 # shortcircuit above
}

function check_loop_device_internal() {
	local device="${1}"
	display_alert "Checking look device" "${device}" "debug"
	if [[ ! -b "${device}" ]]; then
		if [[ $CONTAINER_COMPAT == yes && -b "/tmp/${device}" ]]; then
			display_alert "Creating device node" "${device}"
			run_host_command_logged mknod -m0660 "${device}" b "0x$(stat -c '%t' "/tmp/${device}")" "0x$(stat -c '%T' "/tmp/${device}")"
			if [[ ! -b "${device}" ]]; then # try again after creating node
				return 1                       # fail, it will be retried, and should exist on next retry.
			else
				display_alert "Device node created OK" "${device}" "info"
			fi
		else
			display_alert "Device node does not exist yet" "${device}" "debug"
			run_host_command_logged ls -la "${device}" || true
			run_host_command_logged lsblk || true
			run_host_command_logged blkid || true
			return 1
		fi
	fi

	if [[ "${CHECK_LOOP_FOR_SIZE:-yes}" != "no" ]]; then
		# Device exists. Make sure it's not 0-sized. Read with blockdev --getsize64 /dev/sda
		local device_size
		device_size=$(blockdev --getsize64 "${device}")
		display_alert "Device node size" "${device}: ${device_size}" "debug"
		if [[ ${device_size} -eq 0 ]]; then
			run_host_command_logged ls -la "${device}"
			run_host_command_logged lsblk
			run_host_command_logged blkid
			# only break on the first 3 iteractions. then give up; let it try to use the device...
			if [[ ${RETRY_RUNS} -lt 4 ]]; then
				display_alert "Device node exists but is 0-sized; retry ${RETRY_RUNS}" "${device}" "warn"
				return 1
			else
				display_alert "Device node exists but is 0-sized; proceeding anyway" "${device}" "warn"
			fi
		fi
	fi

	return 0
}

# write_uboot_to_loop_image <loopdev> <full_path_to_uboot_deb>
function write_uboot_to_loop_image() {

	declare loop=$1
	declare uboot_deb=$2
	display_alert "Preparing u-boot bootloader" "LOOP=${loop} - ${uboot_deb}" "info"

	declare full_path_uboot_deb="${uboot_deb}"
	if [[ ! -f "${full_path_uboot_deb}" ]]; then
		exit_with_error "Missing ${full_path_uboot_deb}"
	fi

	declare cleanup_id="" TEMP_DIR=""
	prepare_temp_dir_in_workdir_and_schedule_cleanup "uboot-write" cleanup_id TEMP_DIR # namerefs

	run_host_command_logged dpkg -x "${full_path_uboot_deb}" "${TEMP_DIR}"/

	if [[ ! -f "${TEMP_DIR}/usr/lib/u-boot/platform_install.sh" ]]; then
		exit_with_error "Missing ${TEMP_DIR}/usr/lib/u-boot/platform_install.sh"
	fi

	display_alert "Sourcing u-boot install functions" "${uboot_deb}" "info"
	source "${TEMP_DIR}"/usr/lib/u-boot/platform_install.sh
	set -e # make sure, we just included something that might disable it

	display_alert "Writing u-boot bootloader" "$loop" "info"
	write_uboot_platform "${TEMP_DIR}${DIR}" "$loop" # important: DIR is set in platform_install.sh sourced above.

	export UBOOT_CHROOT_DIR="${TEMP_DIR}${DIR}"

	call_extension_method "post_write_uboot_platform" <<- 'POST_WRITE_UBOOT_PLATFORM'
		*allow custom writing of uboot -- only during image build*
		Called after `write_uboot_platform()`.
		It receives `UBOOT_CHROOT_DIR` with the full path to the u-boot dir in the chroot.
		Important: this is only called inside the build system.
		Consider that `write_uboot_platform()` is also called board-side, when updating uboot, eg: nand-sata-install.
	POST_WRITE_UBOOT_PLATFORM

	done_with_temp_dir "${cleanup_id}" # changes cwd to "${SRC}" and fires the cleanup function early

	return 0
}

# This exists to prevent silly failures; sometimes the user is inspecting the directory outside of build, etc.
function free_loop_device_insistent() {
	display_alert "Freeing loop device" "${1}"
	do_with_retries 10 free_loop_device_retried "${1}"
}

function free_loop_device_retried() {
	if [[ ${RETRY_RUNS} -gt 1 ]]; then
		display_alert "Freeing loop device (try ${RETRY_RUNS})" "${1}"
	fi
	losetup -d "${1}"
}
