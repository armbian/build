#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

# This adds the required host-side dependencies, clones and builds rkusbboot.

enable_extension "rkbin-tools" # which brings in the needed loader binaries for Maskrom -> Loader mode

function add_host_dependencies__rkusbboot() {
	display_alert "Preparing rkusbboot host-side dependencies" "${EXTENSION}" "info"
	EXTRA_BUILD_DEPS+=("build-tools::libudev-dev" "build-tools::libusb-1.0-0-dev" "native-toolchain::build-essential")
}

function extension_finish_config__900_rkusbboot() {
	display_alert "Preparing rkusbboot extension" "${EXTENSION}" "info"
	declare -g -r rkusbboot_dir="${SRC}/cache/sources/rkusbboot"
	declare -g -r rkusbboot_bin_path="${rkusbboot_dir}/rkusbboot"

	# @TODO this should be doable if on a local containerd host with --device=/dev/bus/usb:/dev/bus/usb et al
	# if under docker, exit_with_error; we can't get at the USB needed for rkusbboot.
	if [[ "${ARMBIAN_RUNNING_IN_CONTAINER}" == "yes" ]]; then
		exit_with_error "rkusbboot: running under Docker is not supported. rkusbboot requires direct access to the host USB devices."
	fi

	# Boot blobs will be in the u-boot directory
	display_alert "rkusbboot" "Looking for blobs in BOOTDIR=${BOOTDIR} BOOTSOURCEDIR=${BOOTSOURCEDIR}" "wrn"

	# Determine the SPL Loader to be used. This could be better done in board/family file config.
	declare -g -r rkusbboot_ramboot_blob_tpl="${SRC}/cache/sources/${BOOTSOURCEDIR}/u-boot-rockchip-usb471.bin"
	declare -g -r rkusbboot_ramboot_blob_spl="${SRC}/cache/sources/${BOOTSOURCEDIR}/u-boot-rockchip-usb472.bin"
}

function host_dependencies_ready__rkusbboot() {
	display_alert "Preparing rkusbboot for usage" "${EXTENSION}" "info"

	if [[ ! -f "${rkusbboot_bin_path}" ]]; then
		display_alert "rkusbboot not found, building it" "${EXTENSION}" "info"
		build_rkusbboot
	fi

	check_rkusbboot

	declare rkusbboot_is_device_connected="no"
	list_devices_rkusbboot # early listing of devices at the start of build; gives early recompense if you have a device connected.
}

function run_after_build__rkusbboot() {
	display_alert "Starting RAMBoot process" "${EXTENSION} :: ${rkusbboot_ramboot_blob_tpl}" "warn"

	# check if the blob exists, if not, exit_with_error
	if [[ ! -f "${rkusbboot_ramboot_blob_tpl}" ]]; then
		exit_with_error "rkusbboot: tpl blob not found: '${rkusbboot_ramboot_blob_tpl}'"
	fi
	if [[ ! -f "${rkusbboot_ramboot_blob_spl}" ]]; then
		exit_with_error "rkusbboot: spl blob not found: '${rkusbboot_ramboot_blob_spl}'"
	fi

	flash_image_rkusbboot
}

function wait_for_connected_device_rkusbboot() {
	display_alert "Waiting for device to be connected" "${EXTENSION}" "info"
	rkusbboot_is_device_connected="no"
	list_devices_rkusbboot

	declare -i counter=0
	while [[ "${rkusbboot_is_device_connected}" != "yes" ]]; do
		counter+=1
		display_alert "Waiting for rkusbboot device to be connected (loop ${counter})" "${EXTENSION}" "debug"
		sleep 1
		list_devices_rkusbboot
	done

}

function flash_image_rkusbboot() {
	display_alert "Starting RAMBoot" "${EXTENSION}" "info"

	declare rkusbboot_is_device_connected="no" rkusbboot_device_number="undetermined" rkusbboot_device_pid="not_present"
	wait_for_connected_device_rkusbboot

	display_alert "Executing RAMBoot" "${EXTENSION} -- NOW!" "info"
	"${rkusbboot_bin_path}" "${rkusbboot_ramboot_blob_tpl}" "${rkusbboot_ramboot_blob_spl}"

	return 0
}

function list_devices_rkusbboot() {
	rkusbboot_is_device_connected="no"     # outer scope
	rkusbboot_device_number="undetermined" # outer scope
	rkusbboot_device_pid="not_present"     # outer scope
	display_alert "Listing rkusbboot devices" "${EXTENSION}" "debug"

	declare list_rk_devices_output="undetermined"
	list_rk_devices_output="$("${rkusbboot_bin_path}" -l | head -1)"
	display_alert "rkusbboot -l output" "${EXTENSION} :: '${list_rk_devices_output}'" "debug"

	# If list_devices_rkusbboot is empty, then no device is connected.
	if [[ "${list_rk_devices_output}" == "" ]]; then
		display_alert "No rkusbboot device found." "${EXTENSION}" ""
		display_alert "Use an USB-C cable to connect the Rockchip device to this host." "${EXTENSION}" ""
		display_alert "Power on the Rockchip device and put it in MASKROM mode." "${EXTENSION}" ""
		display_alert "For example, click & hold MaskROM button and then click Reset/Power button." "${EXTENSION}" ""
		display_alert "Or, hold MaskROM button & power the board." "${EXTENSION}" ""
		display_alert "This is try number ${counter:-"0"}" "${EXTENSION}" ""
	else
		# Some device is connected, parse the output.
		# It is something like 'Device #0: PID 0x350e'
		rkusbboot_is_device_connected="yes"
		rkusbboot_device_number=$(echo "${list_rk_devices_output}" | grep -oP 'Device #\K\d+')
		rkusbboot_device_pid=$(echo "${list_rk_devices_output}" | grep -oP 'PID 0x\K[0-9a-fA-F]+')

		display_alert "rkusbboot ld output" "${EXTENSION} :: '${list_rk_devices_output}'" "debug"
		display_alert "rkusbboot device number" "${EXTENSION} :: device '${rkusbboot_device_number}'" "info"
		display_alert "rkusbboot device PID" "${EXTENSION} :: PID '0x${rkusbboot_device_pid}'" "info"
	fi

	return 0
}

function build_rkusbboot() {
	# Clone rkusbboot
	fetch_from_repo "https://github.com/RadxaNaoki/rkusbboot.git" "rkusbboot" "branch:main"

	# Build rkusbboot
	pushd "${rkusbboot_dir}" &> /dev/null || exit_with_error "Fail to cd to rkusbboot: ${rkusbboot_dir}"

	run_host_command_logged pipetty make -j$(nproc)
	run_host_command_logged pipetty ls -la "${rkusbboot_bin_path}"

	popd &> /dev/null || exit_with_error "Fail to cd back to armbian-build"
}

function check_rkusbboot() {
	display_alert "rkusbboot at" "${EXTENSION} :: '${rkusbboot_bin_path}'" ""

	# as a courtesy to the user, install a symlink into /usr/local/bin, so rkusbboot can be called by itself as well
	if [[ -f /usr/local/bin/rkusbboot ]]; then
		run_host_command_logged rm -f /usr/local/bin/rkusbboot
	fi
	run_host_command_logged ln -sf "${rkusbboot_bin_path}" /usr/local/bin/rkusbboot
}

function post_config_uboot_target__rkusbboot_enable_ramboot_uboot() {
	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable RAMBoot images" "info"

	# check if scripts/config exists, otherwise exit_with_error
	if [[ ! -f scripts/config ]]; then
		exit_with_error "rkusbboot: u-boot doesn't have scripts/config, can't enable ramboot. Please only use rkusbboot with mainline u-boot."
	fi

	run_host_command_logged scripts/config --enable CONFIG_ROCKCHIP_MASKROM_IMAGE

	# Check if the config file has been updated with CONFIG_ROCKCHIP_MASKROM_IMAGE=y
	if ! grep -q "CONFIG_ROCKCHIP_MASKROM_IMAGE=y" .config; then
		exit_with_error "rkusbboot: u-boot config not updated with CONFIG_ROCKCHIP_MASKROM_IMAGE=y, can't enable ramboot. Please only use rkusbboot with recent mainline u-boot."
	fi

	display_alert "rkusbboot: u-boot for ${BOARD}/${BRANCH}" "u-boot: CONFIG_ROCKCHIP_MASKROM_IMAGE=y enabled" "info"

	return 0
}
