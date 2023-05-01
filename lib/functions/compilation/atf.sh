#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

compile_atf() {
	if [[ -n "${ATFSOURCE}" && "${ATFSOURCE}" != "none" ]]; then
		display_alert "Downloading sources" "atf" "git"
		fetch_from_repo "$ATFSOURCE" "$ATFDIR" "$ATFBRANCH" "yes"
	fi

	if [[ $CLEAN_LEVEL == *make-atf* ]]; then
		display_alert "Cleaning ATF tree - CLEAN_LEVEL contains 'make-atf'" "$ATFSOURCEDIR" "info"
		(
			cd "${SRC}/cache/sources/${ATFSOURCEDIR}" || exit_with_error "crazy about ${ATFSOURCEDIR}"
			run_host_command_logged make distclean
		)
	else
		display_alert "Not cleaning ATF tree, use CLEAN_LEVEL=make-atf if needed" "CLEAN_LEVEL=${CLEAN_LEVEL}" "debug"
	fi

	local atfdir="$SRC/cache/sources/$ATFSOURCEDIR"
	if [[ $USE_OVERLAYFS == yes ]]; then
		atfdir=$(overlayfs_wrapper "wrap" "$SRC/cache/sources/$ATFSOURCEDIR" "atf_${LINUXFAMILY}_${BRANCH}")
	fi
	cd "$atfdir" || exit

	display_alert "Compiling ATF" "" "info"

	# build aarch64
	if [[ $(dpkg --print-architecture) == amd64 ]]; then

		local toolchain
		toolchain=$(find_toolchain "$ATF_COMPILER" "$ATF_USE_GCC")
		[[ -z $toolchain ]] && exit_with_error "Could not find required toolchain" "${ATF_COMPILER}gcc $ATF_USE_GCC"

		if [[ -n $ATF_TOOLCHAIN2 ]]; then
			local toolchain2_type toolchain2_ver toolchain2
			toolchain2_type=$(cut -d':' -f1 <<< "${ATF_TOOLCHAIN2}")
			toolchain2_ver=$(cut -d':' -f2 <<< "${ATF_TOOLCHAIN2}")
			toolchain2=$(find_toolchain "$toolchain2_type" "$toolchain2_ver")
			[[ -z $toolchain2 ]] && exit_with_error "Could not find required toolchain" "${toolchain2_type}gcc $toolchain2_ver"
		fi

		# build aarch64
	fi

	display_alert "Compiler version" "${ATF_COMPILER}gcc $(eval env PATH="${toolchain}:${PATH}" "${ATF_COMPILER}gcc" -dumpfullversion -dumpversion)" "info"

	local target_make target_patchdir target_files
	target_make=$(cut -d';' -f1 <<< "${ATF_TARGET_MAP}")
	target_patchdir=$(cut -d';' -f2 <<< "${ATF_TARGET_MAP}")
	target_files=$(cut -d';' -f3 <<< "${ATF_TARGET_MAP}")

	advanced_patch "atf" "${ATFPATCHDIR}" "$BOARD" "$target_patchdir" "$BRANCH" "${LINUXFAMILY}-${BOARD}-${BRANCH}"

	# create patch for manual source changes
	if [[ $CREATE_PATCHES_ATF == yes ]]; then
		userpatch_create "atf"
		return 0
	fi

	# - "--no-warn-rwx-segment" is *required* for binutils 2.39 - see https://developer.trustedfirmware.org/T996
	#   - but *not supported* by 2.38, brilliant...
	declare binutils_version binutils_flags_atf=""
	binutils_version=$(env PATH="${toolchain}:${toolchain2}:${PATH}" aarch64-linux-gnu-ld.bfd --version | head -1 | cut -d ")" -f 2 | xargs echo -n)
	display_alert "Binutils version for ATF" "${binutils_version}" "info"
	if linux-version compare "${binutils_version}" ge "2.39"; then
		display_alert "Binutils version for ATF" ">= 2.39, adding --no-warn-rwx-segment" "info"
		binutils_flags_atf="--no-warn-rwx-segment"
	fi

	# - ENABLE_BACKTRACE="0" has been added to workaround a regression in ATF. Check: https://github.com/armbian/build/issues/1157
	run_host_command_logged CCACHE_BASEDIR="$(pwd)" PATH="${toolchain}:${toolchain2}:${PATH}" \
		"CFLAGS='-fdiagnostics-color=always -Wno-error=attributes -Wno-error=incompatible-pointer-types'" \
		"TF_LDFLAGS='${binutils_flags_atf}'" \
		make ENABLE_BACKTRACE="0" LOG_LEVEL="40" BUILD_STRING="armbian" $target_make "${CTHREADS}" "CROSS_COMPILE='$CCACHE $ATF_COMPILER'"

	# @TODO: severely missing logging
	[[ $(type -t atf_custom_postprocess) == function ]] && atf_custom_postprocess 2>&1

	atftempdir=$(mktemp -d) # subject to TMPDIR/WORKDIR, so is protected by single/common error trapmanager to clean-up.
	chmod 700 ${atftempdir}

	# copy files to temp directory
	for f in $target_files; do
		local f_src
		f_src=$(cut -d':' -f1 <<< "${f}")
		if [[ $f == *:* ]]; then
			local f_dst
			f_dst=$(cut -d':' -f2 <<< "${f}")
		else
			local f_dst
			f_dst=$(basename "${f_src}")
		fi
		[[ ! -f $f_src ]] && exit_with_error "ATF file not found" "$(basename "${f_src}")"
		cp "${f_src}" "${atftempdir}/${f_dst}"
	done

	# copy license file to pack it to u-boot package later
	[[ -f license.md ]] && cp license.md "${atftempdir}"/

	return 0 # avoid error due to short-circuit above
}
