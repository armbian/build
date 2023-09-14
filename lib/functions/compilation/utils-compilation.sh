#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
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

	display_alert "SKIP_EXTERNAL_TOOLCHAINS=no, Searching for toolchain" "'${compiler}' '${expression}'" "warn"

	local toolchain=""

	# extract target major.minor version from expression
	local target_ver
	target_ver=$(grep -oE "[[:digit:]]+\.[[:digit:]]" <<< "$expression")
	display_alert "Searching for toolchain" "'${compiler}' '${expression}': target_ver: '${target_ver}'" "debug"

	for dir in "${SRC}"/cache/toolchain/*/; do
		display_alert "Checking toolchain" "${dir}" "debug"
		local gcc_bin="${dir}bin/${compiler}gcc"
		# check if is a toolchain for current $ARCH
		if [[ ! -f "${gcc_bin}" ]]; then
			display_alert "Can't find compiler" "'${dir}' :: '${gcc_bin}" "debug"
			continue
		else
			display_alert "Found compiler" "'${dir}' :: '${gcc_bin}" "debug"
		fi

		declare gcc_bin_info
		gcc_bin_info="$(file "${gcc_bin}" || true)"

		display_alert "Testing toolchain" "'${gcc_bin}': '${gcc_bin_info}'" "debug"

		# get toolchain major.minor version
		declare gcc_ver_simple
		gcc_ver_simple="$("${gcc_bin}" -dumpversion 2>&1 || true)" # this might fail: toolchain can't run on current host

		display_alert "Checking version" "'${gcc_ver_simple}' for '${gcc_bin}'" "debug"
		if [[ "x${gcc_ver_simple}x" == "xx" ]]; then
			display_alert "Can't obtain version" "'${gcc_bin}' for '${gcc_bin}': '${gcc_ver_simple}'" "debug"
			continue
		fi

		declare gcc_ver
		gcc_ver="$(echo "${gcc_ver_simple}" | grep -oE "^[[:digit:]]+\.[[:digit:]]" || true)" # this might fail to parse
		if [[ "x${gcc_ver}x" == "xx" ]]; then
			display_alert "Can't parse version" "'${gcc_bin}' for '${gcc_bin}': '${gcc_ver_simple}': '${gcc_ver}'" "debug"
			continue
		fi

		display_alert "Found working toolchain" "'${gcc_bin}' gcc_ver_simple:'${gcc_ver_simple}' gcc_ver:'${gcc_ver}'" "debug"

		# check if toolchain version satisfies requirement
		if ! awk "BEGIN{exit ! ($gcc_ver $expression)}" > /dev/null; then
			display_alert "Toolchain version" "'${gcc_bin}' '${gcc_ver}' doesn't satisfy '${expression}'" "debug"
			continue
		fi

		# check if found version is the closest to target
		# may need different logic here with more than 1 digit minor version numbers
		# numbers: 3.9 > 3.10; versions: 3.9 < 3.10
		# dpkg --compare-versions can be used here if operators are changed
		declare d
		d=$(awk '{x = $1 - $2}{printf "%.1f\n", (x > 0) ? x : -x}' <<< "$target_ver $gcc_ver")
		if awk "BEGIN{exit ! ($d < $dist)}" > /dev/null; then
			dist="$d"
			toolchain="${dir}bin"
			display_alert "Found toolchain" "'${gcc_bin}' ver:'${gcc_ver}' expression:'${expression}' dist:'${dist}'" "debug"
		fi
	done

	display_alert "Using toolchain" "${toolchain}" "info"

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
