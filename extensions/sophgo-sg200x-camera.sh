#!/usr/bin/env bash
# @description Adds camera support for the Milk-V Duo S J1 and J2 connectors: the SG2000 MIPI CSI-2 receiver and VI raw capture drivers, the sensor drivers that mainline lacks (IMX708, GC2083) and the camera overlays. Copies the pinned `leafpmpmp/sg200x-camera-dkms` sources into the kernel tree and builds them as in-tree modules.

#
# SPDX-License-Identifier: GPL-2.0
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
# Extension: sophgo-sg200x-camera
#
# The camera drivers and overlays live in one repository, at the paths they
# have in the kernel tree (linux/). A new sensor is a commit there and a new
# pin here, not a set of kernel patches per kernel version. The same
# repository also builds as a DKMS package for other kernels.
#
# Changes to drivers that are already in the kernel stay kernel patches in
# patch/kernel/archive/sophgo-sg200x-*: the CCS PLL change that the IMX708
# needs, and DW9817 support in dw9807-vcm.
#
# As in sophgo-sg200x-aic8800, the copy happens from custom_kernel_config, not
# kernel_copy_extra_sources: patching resets the tree and removes untracked
# files, so anything staged earlier is lost.
#

declare -g SG200X_CAMERA_REPO="${SG200X_CAMERA_REPO:-https://github.com/leafpmpmp/sg200x-camera-dkms}"
# Pinned; a mutable branch ref would break kernel build caching.
declare -g SG200X_CAMERA_REF="${SG200X_CAMERA_REF:-commit:2c1ebd5470b44b10f5fbf28f05c438aafb7e5f06}"

# Set the path of the pinned camera sources. The sources are fetched only when
# the kernel builds, see below.
function post_family_config__sophgo_sg200x_camera_src_dir() {
	declare -g SG200X_CAMERA_SRC_DIR="${SRC}/cache/sources/sg200x-camera/${SG200X_CAMERA_REF#*:}"
}

# Copy the pinned drivers and overlays into the kernel tree. Hook them into the
# build and enable them as modules.
function custom_kernel_config__sophgo_sg200x_camera() {
	# Rebuild the kernel when the camera sources change.
	kernel_config_modifying_hashes+=("sophgo_sg200x_camera=${SG200X_CAMERA_REPO}#${SG200X_CAMERA_REF}")

	# Also called during config dumping and version calculation, with no kernel tree.
	[[ ! -f .config ]] && return 0

	# fetch_from_repo changes directory; the rest works relative to the kernel tree.
	declare kernel_cwd="${PWD}"
	fetch_from_repo "${SG200X_CAMERA_REPO}" "sg200x-camera" "${SG200X_CAMERA_REF}" "yes"
	cd "${kernel_cwd}" || exit_with_error "SG200x camera" "could not return to ${kernel_cwd}"

	declare src="${SG200X_CAMERA_SRC_DIR}/linux"
	[[ -d "${src}/drivers" ]] || exit_with_error "SG200x camera" "no linux/ tree in ${SG200X_CAMERA_SRC_DIR}"

	declare media="${kernel_work_dir}/drivers/media"

	# Stop when mainline gains one of these drivers: the copy would replace or
	# duplicate it. Drop the driver from the camera repository then.
	declare dir sensor
	for dir in drivers/media/platform/sophgo drivers/media/i2c/sg200x-camera; do
		if git -C "${kernel_work_dir}" ls-files --error-unmatch "${dir}" &> /dev/null; then
			exit_with_error "SG200x camera" "the kernel has its own ${dir}"
		fi
		run_host_command_logged rm -rf "${kernel_work_dir:?}/${dir}"
	done
	for sensor in VIDEO_GC2083 VIDEO_IMX708; do
		if grep -qx "config ${sensor}" "${media}/i2c/Kconfig"; then
			exit_with_error "SG200x camera" "the kernel has its own ${sensor}"
		fi
	done

	# Copy without the cache's timestamps. The overlay objects stay between
	# builds, so older sources would not rebuild them.
	display_alert "SG200x camera" "adding drivers and overlays to the kernel tree" "info"
	run_host_command_logged cp -r "${src}/." "${kernel_work_dir}/"

	# Hook the new directories into the media Kconfig and Makefiles. The sensors
	# go into the camera sensor menu, which provides their dependencies.
	if ! grep -q "platform/sophgo/Kconfig" "${media}/platform/Kconfig"; then
		sed -i 's|^source "drivers/media/platform/samsung/Kconfig"$|&\nsource "drivers/media/platform/sophgo/Kconfig"|' \
			"${media}/platform/Kconfig"
	fi
	if ! grep -q "i2c/sg200x-camera/Kconfig" "${media}/i2c/Kconfig"; then
		sed -i '0,/^if VIDEO_CAMERA_SENSOR$/s||&\n\nsource "drivers/media/i2c/sg200x-camera/Kconfig"|' \
			"${media}/i2c/Kconfig"
	fi
	if ! grep -q "platform/sophgo/Kconfig" "${media}/platform/Kconfig" ||
		! grep -q "i2c/sg200x-camera/Kconfig" "${media}/i2c/Kconfig"; then
		exit_with_error "SG200x camera" "could not hook the drivers into the media Kconfig"
	fi
	grep -qx "obj-y += sophgo/" "${media}/platform/Makefile" ||
		echo "obj-y += sophgo/" >> "${media}/platform/Makefile"
	grep -qx "obj-y += sg200x-camera/" "${media}/i2c/Makefile" ||
		echo "obj-y += sg200x-camera/" >> "${media}/i2c/Makefile"

	# Build the overlays, and composite DTBs that check that they apply.
	declare arch_dir dts_makefile
	for arch_dir in riscv arm64; do
		dts_makefile="${kernel_work_dir}/arch/${arch_dir}/boot/dts/sophgo/Makefile"
		[[ -f "${dts_makefile}" ]] || continue
		grep -q "sg2000-camera-" "${dts_makefile}" ||
			cat "${SG200X_CAMERA_SRC_DIR}/armbian/Makefile.dts" >> "${dts_makefile}"
	done

	kernel_config_set_y CONFIG_V4L_PLATFORM_DRIVERS
	kernel_config_set_m CONFIG_VIDEO_SOPHGO_CV1800_CSI2
	kernel_config_set_m CONFIG_VIDEO_SOPHGO_CV1800_VI
	kernel_config_set_m CONFIG_VIDEO_GC2083
	kernel_config_set_m CONFIG_VIDEO_IMX708
	kernel_config_set_m CONFIG_VIDEO_OV5647
	kernel_config_set_m CONFIG_VIDEO_DW9807_VCM
}
