#!/usr/bin/env bash
#
# Copyright (c) 2013-2021 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# Functions:

# compile_atf
# compile_uboot
# compile_kernel
# compile_firmware
# compile_armbian-config
# compile_xilinx_bootgen
# grab_version
# find_toolchain
# advanced_patch
# process_patch_file
# userpatch_create
# overlayfs_wrapper

grab_version() {
	local ver=()
	ver[0]=$(grep "^VERSION" "${1}"/Makefile | head -1 | awk '{print $(NF)}' | grep -oE '^[[:digit:]]+' || true)
	ver[1]=$(grep "^PATCHLEVEL" "${1}"/Makefile | head -1 | awk '{print $(NF)}' | grep -oE '^[[:digit:]]+' || true)
	ver[2]=$(grep "^SUBLEVEL" "${1}"/Makefile | head -1 | awk '{print $(NF)}' | grep -oE '^[[:digit:]]+' || true)
	ver[3]=$(grep "^EXTRAVERSION" "${1}"/Makefile | head -1 | awk '{print $(NF)}' | grep -oE '^-rc[[:digit:]]+' || true)
	echo "${ver[0]:-0}${ver[1]:+.${ver[1]}}${ver[2]:+.${ver[2]}}${ver[3]}"
	return 0
}

# find_toolchain <compiler_prefix> <expression>
#
# returns path to toolchain that satisfies <expression>
#
find_toolchain() {
	[[ "${SKIP_EXTERNAL_TOOLCHAINS}" == "yes" ]] && {
		echo "/usr/bin"
		return
	}
	local compiler=$1
	local expression=$2
	local dist=10
	local toolchain=""
	# extract target major.minor version from expression
	local target_ver
	target_ver=$(grep -oE "[[:digit:]]+\.[[:digit:]]" <<< "$expression")
	for dir in "${SRC}"/cache/toolchain/*/; do
		# check if is a toolchain for current $ARCH
		[[ ! -f ${dir}bin/${compiler}gcc ]] && continue
		# get toolchain major.minor version
		local gcc_ver
		gcc_ver=$("${dir}bin/${compiler}gcc" -dumpversion | grep -oE "^[[:digit:]]+\.[[:digit:]]")
		# check if toolchain version satisfies requirement
		awk "BEGIN{exit ! ($gcc_ver $expression)}" > /dev/null || continue
		# check if found version is the closest to target
		# may need different logic here with more than 1 digit minor version numbers
		# numbers: 3.9 > 3.10; versions: 3.9 < 3.10
		# dpkg --compare-versions can be used here if operators are changed
		local d
		d=$(awk '{x = $1 - $2}{printf "%.1f\n", (x > 0) ? x : -x}' <<< "$target_ver $gcc_ver")
		if awk "BEGIN{exit ! ($d < $dist)}" > /dev/null; then
			dist=$d
			toolchain=${dir}bin
		fi
	done
	echo "$toolchain"
}
# overlayfs_wrapper <operation> <workdir> <description>
#
# <operation>: wrap|cleanup
# <workdir>: path to source directory
# <description>: suffix for merged directory to help locating it in /tmp
# return value: new directory
#
# Assumptions/notes:
# - Ubuntu Xenial host
# - /tmp is mounted as tmpfs
# - there is enough space on /tmp
# - UB if running multiple compilation tasks in parallel
# - should not be used with CREATE_PATCHES=yes
#
overlayfs_wrapper() {
	local operation="$1"
	if [[ $operation == wrap ]]; then
		local srcdir="$2"
		local description="$3"
		mkdir -p /tmp/overlay_components/ /tmp/armbian_build/
		local tempdir workdir mergeddir
		tempdir=$(mktemp -d --tmpdir="/tmp/overlay_components/") # @TODO: WORKDIR? otherwise uses host's root disk, which might be small
		workdir=$(mktemp -d --tmpdir="/tmp/overlay_components/")
		mergeddir=$(mktemp -d --suffix="_$description" --tmpdir="/tmp/armbian_build/")
		mount -t overlay overlay -o lowerdir="$srcdir",upperdir="$tempdir",workdir="$workdir" "$mergeddir"
		# this is executed in a subshell, so use temp files to pass extra data outside
		echo "$tempdir" >> /tmp/.overlayfs_wrapper_cleanup
		echo "$mergeddir" >> /tmp/.overlayfs_wrapper_umount
		echo "$mergeddir" >> /tmp/.overlayfs_wrapper_cleanup
		echo "$mergeddir"
		return
	fi
	if [[ $operation == cleanup ]]; then
		if [[ -f /tmp/.overlayfs_wrapper_umount ]]; then
			for dir in $(< /tmp/.overlayfs_wrapper_umount); do
				[[ $dir == /tmp/* ]] && umount -l "$dir" > /dev/null 2>&1
			done
		fi
		if [[ -f /tmp/.overlayfs_wrapper_cleanup ]]; then
			for dir in $(< /tmp/.overlayfs_wrapper_cleanup); do
				[[ $dir == /tmp/* ]] && rm -rf "$dir"
			done
		fi
		rm -f /tmp/.overlayfs_wrapper_umount /tmp/.overlayfs_wrapper_cleanup
	fi
}
