#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

compile_crust() {
	if [[ -n "${CRUSTSOURCE}" && "${CRUSTSOURCE}" != "none" ]]; then
		display_alert "Downloading sources" "crust" "git"
		fetch_from_repo "$CRUSTSOURCE" "$CRUSTDIR" "$CRUSTBRANCH" "yes"
	fi

	if [[ $CLEAN_LEVEL == *make-crust* ]]; then
		display_alert "Cleaning Crust tree - CLEAN_LEVEL contains 'make-crust'" "$CRUSTSOURCEDIR" "info"
		(
			cd "${SRC}/cache/sources/${CRUSTSOURCEDIR}" || exit_with_error "crazy about ${CRUSTSOURCEDIR}"
			run_host_command_logged make distclean
		)
	else
		display_alert "Not cleaning Crust tree, use CLEAN_LEVEL=make-crust if needed" "CLEAN_LEVEL=${CLEAN_LEVEL}" "debug"
	fi

	local crustdir="$SRC/cache/sources/$CRUSTSOURCEDIR"
	if [[ $USE_OVERLAYFS == yes ]]; then
		crustdir=$(overlayfs_wrapper "wrap" "$SRC/cache/sources/$CRUSTSOURCEDIR" "crust_${LINUXFAMILY}_${BRANCH}")
	fi
	cd "$crustdir" || exit

	display_alert "Compiling Crust" "" "info"

	# build aarch64
	if [[ $(dpkg --print-architecture) == amd64 ]]; then

		local toolchain
		toolchain=$(find_toolchain "$CRUST_COMPILER" "$CRUST_USE_GCC")
		[[ -z $toolchain ]] && exit_with_error "Could not find required toolchain" "${CRUST_COMPILER}gcc $CRUST_USE_GCC"
	fi

	display_alert "Compiler version" "${CRUST_COMPILER}gcc $(eval env PATH="${toolchain}:${PATH}" "${CRUST_COMPILER}gcc" -dumpfullversion -dumpversion)" "info"

	local target_make target_patchdir target_files
	target_make=$(cut -d';' -f1 <<< "${CRUST_TARGET_MAP}")
	target_patchdir=$(cut -d';' -f2 <<< "${CRUST_TARGET_MAP}")
	target_files=$(cut -d';' -f3 <<< "${CRUST_TARGET_MAP}")

	advanced_patch "crust" "${CRUSTPATCHDIR}" "$BOARD" "$target_patchdir" "$BRANCH" "${LINUXFAMILY}-${BOARD}-${BRANCH}"

	# create patch for manual source changes
	if [[ $CREATE_PATCHES_CRUST == yes ]]; then
		userpatch_create "crust"
		return 0
	fi

	declare binutils_version binutils_flags_crust=""
	binutils_version=$(env PATH="${toolchain}:${PATH}" or1k-elf-ld.bfd --version | head -1 | cut -d ")" -f 2 | xargs echo -n)
	display_alert "Binutils version for Crust" "${binutils_version}" "info"

	run_host_command_logged CCACHE_BASEDIR="$(pwd)" PATH="${toolchain}:${toolchain2}:${PATH}" \
		"CFLAGS='-fdiagnostics-color=always -Wno-error=attributes -Wno-error=incompatible-pointer-types'" \
		make ${CRUSTCONFIG} "${CTHREADS}" "CROSS_COMPILE='$CCACHE $CRUST_COMPILER'"

	run_host_command_logged CCACHE_BASEDIR="$(pwd)" PATH="${toolchain}:${toolchain2}:${PATH}" \
		"CFLAGS='-fdiagnostics-color=always -Wno-error=attributes -Wno-error=incompatible-pointer-types'" \
		make $target_make "${CTHREADS}" "CROSS_COMPILE='$CCACHE $CRUST_COMPILER'"

	# @TODO: severely missing logging
	[[ $(type -t crust_custom_postprocess) == function ]] && crust_custom_postprocess 2>&1

	crusttempdir=$(mktemp -d) # subject to TMPDIR/WORKDIR, so is protected by single/common error trapmanager to clean-up.
	chmod 700 ${crusttempdir}

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
		[[ ! -f $f_src ]] && exit_with_error "Crust file not found" "$(basename "${f_src}")"
		cp "${f_src}" "${crusttempdir}/${f_dst}"
	done

	# copy license file to pack it to u-boot package later
	[[ -f license.md ]] && cp license.md "${crusttempdir}"/

	return 0 # avoid error due to short-circuit above
}
