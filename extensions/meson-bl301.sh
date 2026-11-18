#!/usr/bin/env bash
# @description Builds BL301, the SCP firmware of Amlogic G12, for ODROID-HC4 from Hardkernel's U-Boot tree plus `patch/bl301/` and packs it into the FIP instead of the prebuilt `bl301.bin` from LibreELEC amlogic-boot-fip. Adds `gcc-arm-none-eabi` to the host dependencies. With these patches the board wakes from suspend-to-RAM on the rtc-meson-vrtc alarm.
#
# SPDX-License-Identifier: GPL-2.0
#
# Build BL301, the SCP firmware of Amlogic G12, for ODROID-HC4 from
# Hardkernel's U-Boot tree plus patch/bl301/, instead of taking the
# prebuilt bl301.bin from LibreELEC/amlogic-boot-fip.
#
# Enable with: enable_extension "meson-bl301" (board config); the board's
# FIP packing must take MESON_BL301_FIP_DIR.
#
# Variables:
#   MESON_BL301_SOURCE     Hardkernel U-Boot repository.
#   MESON_BL301_BRANCH     Pinned ref of that repository.
#   MESON_BL301_PATCHDIR   Directory under patch/bl301/ and userpatches/bl301/.
#   MESON_BL301_DEFCONFIG  Hardkernel defconfig of the board.
#   MESON_BL301_BOARDDIR   Hardkernel board directory holding firmware/scp_task.
#   MESON_BL301_FIP_SRC    amlogic-boot-fip directory the other blobs come from.
# Output:
#   MESON_BL301_FIP_DIR    Copy of MESON_BL301_FIP_SRC with the built bl301.bin,
#                          for uboot_g12_postprocess.

# extension_prepare_config runs only inside Docker; every hook sets the defaults itself.
function _meson_bl301_defaults() {
	declare -g MESON_BL301_SOURCE="${MESON_BL301_SOURCE:-https://github.com/hardkernel/u-boot}"
	declare -g MESON_BL301_BRANCH="${MESON_BL301_BRANCH:-commit:7d5876d36f4120034f1902b12d6799b147bec884}" # odroidg12-v2015.01
	declare -g MESON_BL301_DIR="${MESON_BL301_DIR:-hardkernel-u-boot-odroidg12}"
	declare -g MESON_BL301_PATCHDIR="${MESON_BL301_PATCHDIR:-odroidg12-v2015.01}"
	declare -g MESON_BL301_DEFCONFIG="${MESON_BL301_DEFCONFIG:-odroidc4_defconfig}"
	declare -g MESON_BL301_BOARDDIR="${MESON_BL301_BOARDDIR:-board/hardkernel/odroidc4}"
	declare -g MESON_BL301_FIP_SRC="${MESON_BL301_FIP_SRC:-${SRC}/cache/sources/amlogic-boot-fip/odroid-${BOARD#odroid}}"
}

function add_host_dependencies__meson_bl301_arm_none_eabi() {
	display_alert "${EXTENSION}: adding host dependency" "gcc-arm-none-eabi" "debug"
	EXTRA_BUILD_DEPS+=("cross-other::gcc-arm-none-eabi")
}

function fetch_sources_tools__meson_bl301() {
	_meson_bl301_defaults
	fetch_from_repo "${MESON_BL301_SOURCE}" "${MESON_BL301_DIR}" "${MESON_BL301_BRANCH}"
}

# The u-boot artifact version must change with anything that changes bl301.bin:
# the pinned commit, the patches, and this file with its helper functions.
function post_family_config__meson_bl301_uboot_hash() {
	_meson_bl301_defaults
	declare hash_files="undetermined"
	calculate_hash_for_all_files_in_dirs "${SRC}/patch/bl301/${MESON_BL301_PATCHDIR}" "${USERPATCHES_PATH}/bl301/${MESON_BL301_PATCHDIR}"
	declare bl301_hash
	bl301_hash="$(printf '%s\n' "${hash_files}" "${MESON_BL301_BRANCH}" "${MESON_BL301_DEFCONFIG}" "${MESON_BL301_BOARDDIR}" |
		cat - "${EXTENSION_FILE}" | sha256sum)"
	declare -g UBOOT_HASH_EXTRA="${UBOOT_HASH_EXTRA:+${UBOOT_HASH_EXTRA}-}bl301-${bl301_hash:0:16}"
	display_alert "${EXTENSION}: u-boot hash input" "bl301-${bl301_hash:0:16}" "debug"
}

function pre_config_uboot_target__meson_bl301_build() {
	_meson_bl301_defaults
	if [[ -n "${MESON_BL301_FIP_DIR:-}" ]]; then
		return 0 # built for an earlier u-boot target
	fi
	declare bl301_bin fip_dir
	meson_bl301_build bl301_bin
	fip_dir_with_blob fip_dir "${MESON_BL301_FIP_SRC}" bl301.bin "${bl301_bin}"
	declare -g MESON_BL301_FIP_DIR="${fip_dir}"
	display_alert "${EXTENSION}: FIP blobs with the built bl301.bin" "${MESON_BL301_FIP_DIR}" "info"
}

# meson_bl301_build <out-var>: build bl301.bin in a temporary copy of the tree, store its path in <out-var>.
function meson_bl301_build() {
	declare -n bl301_out="${1}"
	declare src="${SRC}/cache/sources/${MESON_BL301_DIR}"
	declare work
	work="$(mktemp -d)" # under WORKDIR, removed by the common cleanup

	run_host_command_logged git -C "${src}" archive --format=tar -o "${work}/src.tar" HEAD
	run_host_command_logged tar -xf "${work}/src.tar" -C "${work}"
	run_host_command_logged rm -f "${work}/src.tar"

	pushd "${work}" > /dev/null || exit_with_error "${EXTENSION}: cannot enter" "${work}"
	advanced_patch "bl301" "${MESON_BL301_PATCHDIR}" "${BOARD}" "" "${BRANCH}" "${BOARD}-${BRANCH}"
	popd > /dev/null || exit_with_error "${EXTENSION}: cannot leave" "${work}"

	# Kconfig and include/autoconf.mk of the tree; scp_task reads both.
	run_host_command_logged make -C "${work}" O="${work}/build" CROSS_COMPILE="${UBOOT_COMPILER}" "${MESON_BL301_DEFCONFIG}"
	run_host_command_logged make -C "${work}" O="${work}/build" CROSS_COMPILE="${UBOOT_COMPILER}" include/autoconf.mk

	declare commit="${MESON_BL301_BRANCH#commit:}"
	run_host_command_logged make -C "${work}/arch/arm/cpu/armv8/g12a/firmware/scp_task" \
		buildsrc="${work}" buildtree="${work}/build" BOARDDIR="${MESON_BL301_BOARDDIR}" \
		BL301_ID="armbian-${commit:0:12}"

	bl301_out="${work}/build/scp_task/bl301.bin"
	[[ -s "${bl301_out}" ]] || exit_with_error "${EXTENSION}: bl301.bin was not built" "${bl301_out}"
	# blx_fix.sh pads bl301 into a 13312-byte slot and does not check that it fits.
	declare -i size
	size="$(stat -c %s "${bl301_out}")"
	if ((size > 13312)); then
		exit_with_error "${EXTENSION}: bl301.bin is ${size} bytes, the FIP slot holds 13312" "${bl301_out}"
	fi
	display_alert "${EXTENSION}: built bl301.bin" "${size} bytes" "info"
}

# fip_dir_with_blob <out-var> <fip-dir> <blob-name> <blob-file>:
# make a temporary copy of a FIP blob directory with one blob replaced, store its path in <out-var>.
function fip_dir_with_blob() {
	declare -n fip_out="${1}"
	declare fip_src="${2}" blob_name="${3}" blob_file="${4}"
	[[ -f "${fip_src}/${blob_name}" ]] || exit_with_error "${EXTENSION}: no ${blob_name} to replace" "${fip_src}"
	declare dir
	dir="$(mktemp -d)" # under WORKDIR, removed by the common cleanup
	run_host_command_logged cp -a "${fip_src}/." "${dir}/"
	run_host_command_logged cp -v "${blob_file}" "${dir}/${blob_name}"
	# shellcheck disable=SC2034 # nameref: sets the caller's variable
	fip_out="${dir}"
}
