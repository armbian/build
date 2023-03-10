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

		# tar.zst
		["rootfs"]="rootfs"
	)

}
