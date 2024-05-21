#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2024 Ricardo Pardini <ricardo@pardini.net>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

# Enables panthor-gpu overlay and oibaf-mesa extension. Only meant for legacy/vendor branches of Rockchip boards.
enable_extension "mesa-oibaf" # Enable OIBAF repo for mainline mesa

function extension_prepare_config__rk_panthor() {
	display_alert "Preparing rk-panthor" "${EXTENSION}" "info"
	EXTRA_IMAGE_SUFFIXES+=("-panthor") # Add to the image suffix. # global array

	# Enable panthor overlay by default
	declare -g DEFAULT_OVERLAYS="panthor-gpu"

	[[ "${BUILDING_IMAGE}" != "yes" ]] && return 0

	if [[ "${LINUXFAMILY}" != "rockchip-rk3588" && "${LINUXFAMILY}" != "rk35xx" ]]; then
		exit_with_error "${EXTENSION} only works on LINUXFAMILY=rockchip-rk3588/rk35xx, currently on '${LINUXFAMILY}'"
	fi

	if [[ "${BRANCH}" != "vendor" ]]; then
		exit_with_error "${EXTENSION} only works on BRANCH=vendor, currently on '${BRANCH}'"
	fi
}
