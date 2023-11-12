#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/

# This includes a very early script in the initramfs, which checks the kernel command line
# for the presence of "ums=yes", and if found, sets up a USB gadget for UMS (USB Mass Storage)
# exposing all the block devices found in the system.
# After setting this up, it loops forever, so the initramfs doesn't proceed to boot the system.
# This allows the user to connect the board to a host computer, and use it as a USB storage device,
# to flash the eMMC/SD/NVMe/USB/whatever storage device simply using BalenaEtcher or similar tools.

function extension_prepare_config__check_sanity_usb_gadget_ums() {
	display_alert "Checking sanity for" "${EXTENSION} in dir ${EXTENSION_DIR}" "info"
	local script_file_src="${EXTENSION_DIR}/init-premount/usb-gadget-ums.sh"
	if [[ ! -f "${script_file_src}" ]]; then
		exit_with_error "Could not find '${script_file_src}'"
	fi
}


# @TODO: maybe include this in the bsp-cli, so it can be updated later
function pre_customize_image__inject_initramfs_usb_gadget_ums() {
	display_alert "Enabling" "usb-gadget-ums into initramfs" "info"
	local script_file_src="${EXTENSION_DIR}/init-premount/usb-gadget-ums.sh"
	local script_file_dst="${SDCARD}/etc/initramfs-tools/scripts/init-premount/usb-gadget-ums.sh"
	run_host_command_logged cat "${script_file_src}" "|" sed -e "'s|%%BOARD%%|${BOARD}|g'" ">" "${script_file_dst}"
	run_host_command_logged chmod -v +x "${script_file_dst}"
	return 0
}

