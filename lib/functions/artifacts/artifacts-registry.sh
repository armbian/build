#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function armbian_register_artifacts() {

	declare -g -A ARMBIAN_ARTIFACTS_TO_HANDLERS_DICT=(
		# deb-tar
		["kernel"]="kernel"

		# deb
		["u-boot"]="uboot"
		["uboot"]="uboot"
		["firmware"]="firmware"
		["full_firmware"]="full_firmware"
		["fake_ubuntu_advantage_tools"]="fake_ubuntu_advantage_tools"
		["armbian-config"]="armbian-config"
		["armbian-zsh"]="armbian-zsh"
		["armbian-plymouth-theme"]="armbian-plymouth-theme"
		["armbian-bsp-cli"]="armbian-bsp-cli"
		["armbian-bsp-desktop"]="armbian-bsp-desktop"
		["armbian-desktop"]="armbian-desktop"

		# tar.zst
		["rootfs"]="rootfs"
	)

}
