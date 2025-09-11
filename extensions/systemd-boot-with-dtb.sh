#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2025 Mecid Urganci <mecid@meco.media>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

# `systemd-boot-with-dtb` is a superset of `systemd-boot`, but enhanced to boot using DeviceTree.
# This is useful for ARM64 devices that require DTB files.

enable_extension "systemd-boot"

# Ensure config is sufficient for operation
function extension_prepare_config__prepare_systemd_boot_with_dtb() {
	# Make sure BOOT_FDT_FILE is set and not empty
	[[ -n "${BOOT_FDT_FILE}" ]] || exit_with_error "BOOT_FDT_FILE is not set, required for systemd-boot-with-dtb"

	display_alert "Extension: ${EXTENSION}: Initializing config" "${BOARD}" "info"
}

# Additional hook to ensure DTB is properly configured for systemd-boot
function systemd_boot_early_config__prepare_dtb_directory() {
	display_alert "Extension: ${EXTENSION}: Setting up DTB directory" "${BOOT_FDT_FILE}" "info"

	# Make sure the DTB directory exists in ESP
	mkdir -p "${MOUNT}/boot/efi/dtb"

	# The directory structure in ESP should mirror the one in the kernel DTB path
	local dtb_dir=$(dirname "${BOOT_FDT_FILE}")
	if [[ "${dtb_dir}" != "." ]]; then
		mkdir -p "${MOUNT}/boot/efi/dtb/${dtb_dir}"
	fi
}

function systemd_boot_pre_install__prepare_dtb_files() {
	display_alert "Extension: ${EXTENSION}: Preparing DTB files" "${BOARD}" "info"

	# For each kernel installed in the image, copy the DTB file to the ESP
	for kernel_version in $(find "${MOUNT}/boot" -name "vmlinuz-*" | sed 's|.*/vmlinuz-||'); do
		display_alert "Extension: ${EXTENSION}: Processing DTB for kernel" "${kernel_version}" "debug"

		# Source DTB path in kernel directory
		local source_dtb="${MOUNT}/usr/lib/linux-image-${kernel_version}/${BOOT_FDT_FILE}"

		# Target DTB path in ESP
		local target_dtb="${MOUNT}/boot/efi/dtb/${BOOT_FDT_FILE}"

		# Create directory structure if needed
		mkdir -p "$(dirname "${target_dtb}")"

		# Copy DTB file if it exists
		if [[ -f "${source_dtb}" ]]; then
			display_alert "Extension: ${EXTENSION}: Copying DTB for kernel ${kernel_version}" "${BOOT_FDT_FILE}" "debug"
			cp -v "${source_dtb}" "${target_dtb}"
		else
			display_alert "Extension: ${EXTENSION}: DTB file not found for kernel ${kernel_version}" "${source_dtb}" "warn"
		fi
	done
}

function systemd_boot_late_config__check_dtb_in_entries() {
	display_alert "Extension: ${EXTENSION}: Verifying DTB entries" "${BOARD}" "info"

	if [[ "${SHOW_DEBUG}" == "yes" ]]; then
		display_alert "Extension: ${EXTENSION}: Debugging" "systemd-boot entries and /boot/efi contents" "info"
		run_host_command_logged ls -la --color=always "${MOUNT}/boot/efi/loader/entries"
		run_host_command_logged find "${MOUNT}/boot/efi" -name "*.dtb" -o -path "*dtb/*"

		# Show the content of the entries
		for entry_file in $(find "${MOUNT}/boot/efi/loader/entries" -name "*.conf"); do
			run_tool_batcat "${entry_file}"
		done
	fi

	# Check if the devicetree entry is present in at least one boot entry
	if ! grep -q 'devicetree' "${MOUNT}"/boot/efi/loader/entries/*.conf 2>/dev/null; then
		display_alert "Extension: ${EXTENSION}: Sanity check failed" "systemd-boot DTB not found in any entry; RELEASE=${RELEASE}" "warn"
	else
		display_alert "Extension: ${EXTENSION}: Sanity check passed" "systemd-boot DTB found in entries; RELEASE=${RELEASE}" "info"
	fi

	# Check if DTB file actually exists in ESP
	local dtb_basename=$(basename "${BOOT_FDT_FILE}")
	if ! find "${MOUNT}/boot/efi" -name "${dtb_basename}" | grep -q .; then
		display_alert "Extension: ${EXTENSION}: Sanity check failed" "DTB file not found in ESP: ${dtb_basename}" "warn"
	else
		display_alert "Extension: ${EXTENSION}: Sanity check passed" "DTB file found in ESP: ${dtb_basename}" "info"
	fi

	return 0
}
