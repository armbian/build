#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

# Copy the Rockchip loader binary (e.g. idbloader.img) to output/loader/
# when RK_LOADER_BIN is set in the family or board configuration.

# This binary is required for Rockchip boards to boot from MASKROM mode into LOADER mode.
# Once in LOADER mode, rkdeveloptool can be used to erase / flash the NAND / eMMC storage onboard.

function post_uboot_custom_postprocess__copy_rk_loader_bin() {
	[[ -z "${RK_LOADER_BIN}" ]] && return 0

	if [[ ! -f "${RK_LOADER_BIN}" ]]; then
		exit_with_error "RK_LOADER_BIN file not found in u-boot build directory" "${RK_LOADER_BIN}"
	fi

	display_alert "Copying Rockchip loader binary" "${RK_LOADER_BIN} -> output/loader/${BOARD}-${RK_LOADER_BIN}" "info"
	mkdir -p "${DEST}/loader"
	run_host_command_logged cp -v "${RK_LOADER_BIN}" "${DEST}/loader/${BOARD}-${RK_LOADER_BIN}"
}
