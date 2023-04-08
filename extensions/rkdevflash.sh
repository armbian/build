#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

# This adds the required host-side dependencies, clones and builds rkdeveloptool.
# When build is done, it enters a loop to wait for the device to be connected.
# When the device is connected, it check if device is in Maskrom or Loader mode.
# If in Markrom mode: use the ROCKUSB_BLOB to init Loader mode.
# If in Loader mode: it flashes the device with the produced image.
# It then resets the device via rkdeveloptool rd.

enable_extension "rkbin-tools" # which brings in the needed loader binaries for Maskrom -> Loader mode

function add_host_dependencies__rkdevflash() {
	display_alert "Preparing rkdevflash host-side dependencies" "${EXTENSION}" "info"
	declare -g EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} libudev-dev libusb-1.0-0-dev dh-autoreconf build-essential" # @TODO: convert to array later
}

function extension_finish_config__900_rkdevflash() {
	display_alert "Preparing rkdevflash extension" "${EXTENSION}" "info"
	declare -g -r rkdeveloptool_dir="${SRC}/cache/sources/rkdeveloptool"
	declare -g -r rkdeveloptool_bin_path="${rkdeveloptool_dir}/rkdeveloptool"

	# if under docker, exit_with_error; we can't get at the USB needed for rkdeveloptool.
	if [[ "${ARMBIAN_RUNNING_IN_CONTAINER}" == "yes" ]]; then
		exit_with_error "rkdevflash: running under Docker is not supported. rkdeveloptool requires direct access to the host USB devices."
	fi

	# Determine the SPL Loader to be used. This could be better done in board/family file config.
	declare -g rkdeveloptool_spl_loader_blob="${ROCKUSB_BLOB:-"undetermined"}"
	if [[ "${rkdeveloptool_spl_loader_blob}" == "undetermined"* ]]; then
		exit_with_error "rkdevflash: ROCKUSB_BLOB is unset, unsupported LINUXFAMILY '${LINUXFAMILY}'?"
	fi
	declare -g -r rkdeveloptool_spl_loader_blob="${rkdeveloptool_spl_loader_blob}"
	declare -g -r rkdeveloptool_spl_loader_blob_path="${SRC}/cache/sources/rkbin-tools/${rkdeveloptool_spl_loader_blob}"

}

function host_dependencies_ready__rkdevflash() {
	display_alert "Preparing rkdevflash for usage" "${EXTENSION}" "info"

	if [[ ! -f "${rkdeveloptool_bin_path}" ]]; then
		display_alert "rkdeveloptool not found, building it" "${EXTENSION}" "info"
		build_rkdeveloptool
	fi

	fetch_sources_tools__rkbin_tools # explicit call to extension method; we need the rkbins early.

	if [[ ! -f "${rkdeveloptool_spl_loader_blob_path}" ]]; then
		exit_with_error "rkdevflash: SPL loader blob not found: '${rkdeveloptool_spl_loader_blob_path}'"
	fi

	check_rkdeveloptool # logs the version of rkdeveloptool

	display_alert "rkdevflash using RockUSB loader blob" "${EXTENSION} :: ${rkdeveloptool_spl_loader_blob}" "info"

	declare rkdeveloptool_is_device_connected="no" rkdeveloptool_device_id="" rkdeveloptool_device_mode=""
	list_devices_rkdeveloptool # early listing of devices at the start of build; gives early recompense if you have a device connected.
}

function post_build_image_write__rkdevflash() {
	: "${built_image_file:?built_image_file is not set}" # check built_image_file is set
	display_alert "Starting flash process" "${EXTENSION} :: ${built_image_file}" "info"
	flash_image_rkdeveloptool "${built_image_file}"
}

function wait_for_connected_device_rkdeveloptool() {
	display_alert "Waiting for device to be connected" "${EXTENSION}" "info"
	rkdeveloptool_is_device_connected="no" rkdeveloptool_device_id="" rkdeveloptool_device_mode=""
	list_devices_rkdeveloptool

	while [[ "${rkdeveloptool_is_device_connected}" != "yes" ]]; do
		display_alert "Waiting for rkdeveloptool device to be connected" "${EXTENSION}" "debug"
		sleep 1
		list_devices_rkdeveloptool
	done

}

function flash_image_rkdeveloptool() {
	if [[ ! -f "${1}" ]]; then
		exit_with_error "rkdevflash: Image file not found: '${1}'"
	fi

	display_alert "Flashing image" "${EXTENSION} :: ${1}" "info"

	declare rkdeveloptool_is_device_connected="no" rkdeveloptool_device_id="" rkdeveloptool_device_mode=""
	wait_for_connected_device_rkdeveloptool

	while [[ "${rkdeveloptool_device_mode}" != "Loader" ]]; do
		wait_for_connected_device_rkdeveloptool
		if [[ "${rkdeveloptool_device_mode}" == "Maskrom" ]]; then
			display_alert "Loading SPL RockUSB loader" "${EXTENSION} :: ${rkdeveloptool_spl_loader_blob}" "info"
			declare loader_worked="no"
			timeout 10 "${rkdeveloptool_bin_path}" db "${rkdeveloptool_spl_loader_blob_path}" && loader_worked="yes" || true
			if [[ "${loader_worked}" != "yes" ]]; then
				display_alert "rkdevflash: Failed to load SPL RockUSB loader. Timeout? Please reset the Rockchip device (again) into recovery..." "${EXTENSION}" "wrn"
				sleep 5
			else
				display_alert "RockUSB Loader deployed, waiting for Loader mode to kick in" "${EXTENSION}" "cachehit"
				sleep 3
			fi
		fi
	done

	wait_for_connected_device_rkdeveloptool
	if [[ "${rkdeveloptool_device_mode}" == "Loader" ]]; then
		display_alert "Flashing image" "${EXTENSION} :: ${1}" "info"
		"${rkdeveloptool_bin_path}" wl 0x0 "${1}"
		display_alert "Restarting device after flash" "${EXTENSION}" "ext"
		"${rkdeveloptool_bin_path}" rd
	else
		display_alert "Device is not in Loader mode, cannot flash" "${EXTENSION} :: ${1}" "wrn"
	fi
}

function list_devices_rkdeveloptool() {
	rkdeveloptool_is_device_connected="no"  # outer scope
	rkdeveloptool_device_id="undetermined"  # outer scope
	rkdeveloptool_device_mode="not_present" # outer scope
	display_alert "Listing rkdeveloptool devices" "${EXTENSION}" "debug"
	if ! "${rkdeveloptool_bin_path}" ld &> /dev/null; then
		display_alert "No rkdeveloptool device found." "${EXTENSION}" ""
		display_alert "Use an USB-C cable to connect the Rockchip device to this host." "${EXTENSION}" ""
		display_alert "Power on the Rockchip device and put it in recovery mode." "${EXTENSION}" ""
		display_alert "For example, click & hold Recovery button and then click Reset button once." "${EXTENSION}" ""
	else
		# Some device is connected, run again and parse the id and mode.
		declare rkdeveloptool_ld_output
		rkdeveloptool_ld_output="$("${rkdeveloptool_bin_path}" ld || echo -n none)"
		if [[ "${rkdeveloptool_ld_output}" == *"none"* ]]; then
			return 0
		fi

		rkdeveloptool_is_device_connected="yes"

		# cleanup the output, rk messes it up so badly it hurts
		rkdeveloptool_ld_output="$(echo "${rkdeveloptool_ld_output}" | tr -d '\r')"              # cleanup
		rkdeveloptool_ld_output="$(echo "${rkdeveloptool_ld_output}" | head -1 | xargs echo -n)" # cleanup
		rkdeveloptool_device_id="$(echo "${rkdeveloptool_ld_output}" | cut -d' ' -f2)"           # 2/3 column
		rkdeveloptool_device_mode="$(echo "${rkdeveloptool_ld_output}" | cut -d' ' -f3)"         # 3/3 column

		display_alert "rkdeveloptool ld output" "${EXTENSION} :: '${rkdeveloptool_ld_output}'" "debug"
		display_alert "rkdeveloptool device detected" "${EXTENSION} :: device '${rkdeveloptool_device_id}'" "info"
		display_alert "rkdeveloptool device mode" "${EXTENSION} :: mode '${rkdeveloptool_device_mode}'" "info"
	fi

	return 0
}

function build_rkdeveloptool() {
	# Clone rkdeveloptool
	#fetch_from_repo "https://github.com/rockchip-linux/rkdeveloptool" "rkdeveloptool" "branch:master" # pristine rk
	fetch_from_repo "https://github.com/radxa/rkdeveloptool.git" "rkdeveloptool" "branch:master" # Radxa's fork has fixes

	# Build rkdeveloptool
	pushd "${rkdeveloptool_dir}" &> /dev/null || exit_with_error "Fail to cd to rkdeveloptool: ${rkdeveloptool_dir}"

	# Patch `-Werror` out of Makefile so it builds with a warning. It still works.
	# sed -i -e 's/-Werror //' Makefile.am || exit_with_error "Fail to patch Makefile.am" # Not needed with Radxa's fork

	run_host_command_logged pipetty aclocal
	run_host_command_logged pipetty autoreconf -i
	run_host_command_logged pipetty autoheader
	run_host_command_logged pipetty automake --add-missing
	run_host_command_logged pipetty ./configure
	run_host_command_logged pipetty make -j$(nproc)
	run_host_command_logged pipetty ls -la "${rkdeveloptool_bin_path}"

	popd &> /dev/null || exit_with_error "Fail to cd back to armbian-build"
}

function check_rkdeveloptool() {
	declare rkdevtool_version="undetermined"
	rkdevtool_version="$("${rkdeveloptool_bin_path}" --version)"
	rkdevtool_version="$(echo "${rkdevtool_version}" | tr -dc '[:print:]' | xargs echo -n)" # cleanup, rk emits a carriage return we don't want
	display_alert "rkdeveloptool version" "${EXTENSION} :: '${rkdevtool_version}'" ""

	# as a courtesy to the user, install a symlink into /usr/local/bin, so rkdeveloptool can be called by itself as well
	if [[ -f /usr/local/bin/rkdeveloptool ]]; then
		run_host_command_logged rm -f /usr/local/bin/rkdeveloptool
	fi
	run_host_command_logged sudo ln -sf "${rkdeveloptool_bin_path}" /usr/local/bin/rkdeveloptool
}
