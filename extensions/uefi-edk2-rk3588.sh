#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/

enable_extension "grub-with-dtb"
enable_extension "initramfs-usb-gadget-ums"

function extension_prepare_config__config_uefi_edk2_rk3588() {
	display_alert "Configuring UEFI EDK2 for RK3588" "${BOARD} - edk2 '${UEFI_EDK2_BOARD_ID}'" "info"

	declare -g GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE_LINUX_DEFAULT:-"acpi=off"}" # default to acpi=off
	declare -g UEFI_GRUB_TIMEOUT=${UEFI_GRUB_TIMEOUT:-3}                              # Default 3-seconds timeout for GRUB menu.
	declare -g UEFI_GRUB_TERMINAL="gfxterm serial console"                            # gfxterm is a long shot.

	# Check that UEFI_EDK2_BOARD_ID is set, or bomb
	if [[ -z "${UEFI_EDK2_BOARD_ID}" ]]; then
		exit_with_error "UEFI_EDK2_BOARD_ID is not set. Please set it to the correct value for your board."
	fi

	# Check that the image is a GPT image.
	if [[ "${IMAGE_PARTITION_TABLE}" != "gpt" ]]; then
		display_alert "Changing partition table to GPT" "original image partition table was ${IMAGE_PARTITION_TABLE}" "warn"
		declare -g IMAGE_PARTITION_TABLE="gpt"
	fi

	# If BOOTFS_TYPE is set, warn and unset it.
	if [[ -n "${BOOTFS_TYPE}" ]]; then
		display_alert "Unsetting BOOTFS_TYPE" "UEFI EDK2 requires BOOTFS_TYPE to be unset, but is set to '${BOOTFS_TYPE}'" "warn"
		unset BOOTFS_TYPE
	fi

	# Add a suffix to the image version, so people know what is is in it.
	EXTRA_IMAGE_SUFFIXES+=("-edk2")

	return 0
}

# This writes the edk2 img to the image, hopefully without destroying the GPT. See https://github.com/edk2-porting/edk2-rk3588#updating-the-firmware
function post_umount_final_image__write_edk2_to_image() {
	display_alert "Finding edk2 latest version" "from GitHub" "info"

	# Find the latest version of edk2-porting from GitHub, using JSON API, curl and jq.
	declare api_url="https://api.github.com/repos/edk2-porting/edk2-rk3588/releases/latest"
	declare latest_version
	latest_version=$(curl -s "${api_url}" | jq -r '.tag_name')
	display_alert "Latest version of edk2-porting is" "${latest_version}" "info"

	# Prepare the cache dir
	declare edk2_cache_dir="${SRC}/cache/edk2-rk3588"
	mkdir -p "${edk2_cache_dir}"

	declare edk2_img_filename="${UEFI_EDK2_BOARD_ID}_UEFI_Release_${latest_version}.img"
	declare -g -r edk2_img_path="${edk2_cache_dir}/${edk2_img_filename}" # global readonly
	display_alert "UEFI EDK2 image path" "${edk2_img_path}" "info"

	declare download_url="https://github.com/edk2-porting/edk2-rk3588/releases/download/${latest_version}/${edk2_img_filename}"

	# Download the image (with wget) if it doesn't exist; download to a temporary file first, then move to the final path.
	if [[ ! -f "${edk2_img_path}" ]]; then
		display_alert "Downloading UEFI EDK2 image" "${download_url}" "info"
		declare tmp_edk2_img_path="${edk2_img_path}.tmp"
		run_host_command_logged wget -O "${tmp_edk2_img_path}" "${download_url}"
		run_host_command_logged mv -v "${tmp_edk2_img_path}" "${edk2_img_path}"
	else
		display_alert "UEFI EDK2 image already downloaded, using it" "${edk2_img_path}" "info"
	fi

	display_alert " Writing UEFI EDK2 image" "${edk2_img_path} to ${LOOP}" "info"
	# Write the whole uefi image, but skip the GPT...
	dd if="${edk2_img_path}" of="${LOOP}" bs=512 conv=notrunc skip=64 seek=64

	# ... Use parted to create "uboot" GPT partition pointing to the FIT image, so SPL finds it
	display_alert "Creating uboot partition" "on ${LOOP}" "info"
	/sbin/parted -s "${LOOP}" unit s mkpart uboot 2048 18431
}
