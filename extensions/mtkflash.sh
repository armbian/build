#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2026 Ricardo Pardini <ricardo@pardini.net>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

# This adds the required host-side dependencies, clones and builds mtk-flash.
# mtk-flash is a rust application, so the rust toolchain is required.
# When build is done, it flashes the device with the produced lk.bin/fip.img and disk image.
# Mediatek devices show up as ttyACMx devices when in flashing mode.
# Some common UART devices and modems might _also_ use ttyACMx.
# If you can predict which ttyACMx to use for flashing, pass it via eg MTKFLASH_TTYACM_DEVICE=1
#   otherwise MTKFLASH_TTYACM_DEVICE=0 is used by default.

function add_host_dependencies__mtkflash() {
	display_alert "Preparing mtkflash host-side dependencies" "${EXTENSION}" "info"
	declare -g EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} rustc cargo build-essential" # @TODO: convert to array later
}

function extension_finish_config__900_mtkflash() {
	display_alert "Preparing mtkflash extension" "${EXTENSION}" "info"

	#declare -g -r MTKFLASH_GIT_REPO="${MTKFLASH_GIT_REPO:-"${GITHUB_SOURCE}/grinn-global/mtk-flash.git"}"
	#declare -g -r MTKFLASH_GIT_COMMIT="${MTKFLASH_GIT_COMMIT:-"2aa9ce8a0398a5ea67180df9178b0725de9ce259"}"
	# TODO: Back to upstream when https://github.com/grinn-global/mtk-flash/pull/2 is merged
	declare -g -r MTKFLASH_GIT_REPO="${MTKFLASH_GIT_REPO:-"${GITHUB_SOURCE}/rpardini/mtk-flash.git"}"
	declare -g -r MTKFLASH_GIT_COMMIT="${MTKFLASH_GIT_COMMIT:-"b29e79e841513d46b45717a1f6334bc48ae8abd3"}"

	declare -g -r mtkflash_dir="${SRC}/cache/sources/mtk-flash"
	declare -g -r mtkflash_bin_path="${mtkflash_dir}/target/release/mtk-flash-${MTKFLASH_GIT_COMMIT}"

	# if under docker, exit_with_error; we can't get at the USB needed.
	if [[ "${ARMBIAN_RUNNING_IN_CONTAINER}" == "yes" ]]; then
		exit_with_error "mtkflash: running under Docker is not supported. it requires direct access to the host USB devices."
	fi
}

function host_dependencies_ready__mtkflash() {
	display_alert "Preparing mtkflash for usage" "${EXTENSION}" "info"

	if [[ ! -f "${mtkflash_bin_path}" ]]; then
		display_alert "mtkflash not found, building it" "${EXTENSION}" "info"
		build_mtkflash
	fi

	check_mtkflash # logs the version of mtkflash
}

# post_build_image_write hooks are called in logging context, which is not so great for interactive flashing tools.
# we probably should introduce a different hook that runs outside logging context for such tools.
function post_build_image_write__mtkflash() {
	: "${built_image_file:?built_image_file is not set}" # check built_image_file is set
	display_alert "Starting mtk-flash flashing process" "${EXTENSION} :: ${built_image_file}" "info"

	# Check the built image file exists
	if [[ ! -f "${built_image_file}" ]]; then
		exit_with_error "mtkflash: Built image file not found: '${built_image_file}'"
	fi

	# We also need the lk.bin and fip.img file. Obtain their names by replacing the image file extension '.img' with '.lk.bin' and '.fip.img'
	declare lk_bin_file="${built_image_file%.img}.lk.bin"
	declare fip_img_file="${built_image_file%.img}.fip.img"
	if [[ ! -f "${lk_bin_file}" ]]; then
		exit_with_error "mtkflash: LK binary file not found: '${lk_bin_file}'"
	fi
	if [[ ! -f "${fip_img_file}" ]]; then
		exit_with_error "mtkflash: FIP image file not found: '${fip_img_file}'"
	fi

	# Handle the ttyACMx device selection via MTKFLASH_TTYACM_DEVICE environment variable.
	# Default to 0 if not set; user can override it.
	# If user-set MTKFLASH_TTYACM_DEVICE begins with a slash, use it as full device path.
	# Otherwise assume it's a number and append to /dev/ttyACM.
	declare mtkflash_device_path="/dev/ttyACM0"
	if [[ -n "${MTKFLASH_TTYACM_DEVICE:-""}" ]]; then
		if [[ "${MTKFLASH_TTYACM_DEVICE}" == /* ]]; then
			mtkflash_device_path="${MTKFLASH_TTYACM_DEVICE}"
		else
			mtkflash_device_path="/dev/ttyACM${MTKFLASH_TTYACM_DEVICE}"
		fi
	fi

	declare -a mtkflash_cmd_args=()

	display_alert "mtk-flash flashing disk image file" "${built_image_file}" "info"
	mtkflash_cmd_args+=("--img" "${built_image_file}")
	display_alert "mtk-flash flashing LK binary file" "${lk_bin_file}" "info"
	mtkflash_cmd_args+=("--da" "${lk_bin_file}")
	display_alert "mtk-flash flashing FIP image file" "${fip_img_file}" "info"
	mtkflash_cmd_args+=("--fip" "${fip_img_file}")

	display_alert "mtk-flash using ttyACM device" "${mtkflash_device_path} (customize with MTKFLASH_TTYACM_DEVICE if needed)" "info"
	mtkflash_cmd_args+=("--dev" "${mtkflash_device_path}")

	mtkflash_cmd_args+=("--no-erase-boot1") # always preserve mmc0boot1 - used for u-boot environment storage

	display_alert "mtk-flash command line" "${mtkflash_bin_path} ${mtkflash_cmd_args[*]@Q}" "debug"

	# Since I hit this before: if the device exists at this stage, it's very likely a conflict with some modem or UART.
	# The device should only appear when user puts the board in flashing mode, not before.
	# If the mtkflash_device_path exists, and is a character device, warn the user to use MTKFLASH_TTYACM_DEVICE.
	if [[ -c "${mtkflash_device_path}" ]]; then
		display_alert "Warning: mtkflash device '${mtkflash_device_path}' already exists before you were asked to set the board to flashing mode." "${EXTENSION}" "warn"
		display_alert "This may indicate a conflict with some modem or UART device using a ttyACMx device." "${EXTENSION}" "warn"
		display_alert "Ensure you have the correct device path set via MTKFLASH_TTYACM_DEVICE environment variable." "${EXTENSION}" "warn"
	else
		display_alert "mtkflash device '${mtkflash_device_path}' (correctly) does not exist - hopefully it will show up when board is put in flashing mode." "${EXTENSION}" "info"
	fi

	# let user know to put the device in flashing mode
	display_alert "NOW! is the time to put the Mediatek board in flashing mode" "${EXTENSION}" "ext"

	# finally run mtk-flash with the accumulated arguments
	"${mtkflash_bin_path}" "${mtkflash_cmd_args[@]}"
}

function build_mtkflash() {
	# Clone mtkflash
	fetch_from_repo "${MTKFLASH_GIT_REPO}" "mtk-flash" "commit:${MTKFLASH_GIT_COMMIT}"

	# Build mtkflash
	pushd "${mtkflash_dir}" &> /dev/null || exit_with_error "Fail to cd to mtkflash: ${mtkflash_dir}"

	run_host_command_logged pipetty cargo build --release

	# If build succeeded, rename the bin with the commit SHA1 for later up-to-date checks
	run_host_command_logged pipetty ls -la "${mtkflash_dir}/target/release/mtk-flash"
	run_host_command_logged mv -v "${mtkflash_dir}/target/release/mtk-flash" "${mtkflash_bin_path}"
	run_host_command_logged pipetty ls -la "${mtkflash_bin_path}"

	popd &> /dev/null || exit_with_error "Fail to cd back to armbian-build"
}

function check_mtkflash() {
	declare mtkflash_version="undetermined"
	mtkflash_version="$("${mtkflash_bin_path}" --version)"
	display_alert "mtkflash version" "${EXTENSION} :: '${mtkflash_version}'" ""

	# as a courtesy to the user, install a symlink into /usr/local/bin, so mtk-flash can be called by itself as well
	# either way never fail due to this
	if [[ -f /usr/local/bin/mtk-flash ]]; then
		run_host_command_logged rm -f /usr/local/bin/mtk-flash || true
	fi
	run_host_command_logged sudo ln -sf "${mtkflash_bin_path}" /usr/local/bin/mtk-flash || true
}
