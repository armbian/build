#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

compile_opensbi() {
	if [[ -n "${OPENSBISOURCE}" && "${OPENSBISOURCE}" != "none" ]]; then
		display_alert "Downloading sources" "opensbi" "git"
		fetch_from_repo "$OPENSBISOURCE" "$OPENSBIDIR" "$OPENSBIBRANCH" "yes"
	fi

	if [[ $CLEAN_LEVEL == *make-opensbi* ]]; then
		display_alert "Cleaning OpenSBI tree - CLEAN_LEVEL contains 'make-opensbi'" "$ATFSOURCEDIR" "info"
		(
			cd "${SRC}/cache/sources/${OPENSBISOURCEDIR}" || exit_with_error "crazy about ${OPENSBISOURCEDIR}"
			run_host_command_logged make distclean
		)
	else
		display_alert "Not cleaning OpenSBI tree, use CLEAN_LEVEL=make-opensbi if needed" "CLEAN_LEVEL=${CLEAN_LEVEL}" "debug"
	fi

	local opensbidir="$SRC/cache/sources/$OPENSBISOURCEDIR"
	if [[ $USE_OVERLAYFS == yes ]]; then
		opensbidir=$(overlayfs_wrapper "wrap" "$SRC/cache/sources/$OPENSBISOURCEDIR" "atf_${LINUXFAMILY}_${BRANCH}")
	fi
	cd "$opensbidir" || exit

	display_alert "Compiling OpenSBI" "" "info"

	# build aarch64
	if [[ $(dpkg --print-architecture) == amd64 ]]; then

		local toolchain
		toolchain=$(find_toolchain "$OPENSBI_COMPILER" "$OPENSBI_USE_GCC")
		[[ -z $toolchain ]] && exit_with_error "Could not find required toolchain" "${OPENSBI_COMPILER}gcc $OPENSBI_USE_GCC"

		if [[ -n $OPENSBI_TOOLCHAIN2 ]]; then
			local toolchain2_type toolchain2_ver toolchain2
			toolchain2_type=$(cut -d':' -f1 <<< "${OPENSBI_TOOLCHAIN2}")
			toolchain2_ver=$(cut -d':' -f2 <<< "${OPENSBI_TOOLCHAIN2}")
			toolchain2=$(find_toolchain "$toolchain2_type" "$toolchain2_ver")
			[[ -z $toolchain2 ]] && exit_with_error "Could not find required toolchain" "${toolchain2_type}gcc $toolchain2_ver"
		fi

		# build aarch64
	fi

	# @FIXME: Eval is dangerous, rewrite to avoid using it or sanitize
	display_alert "Compiler version" "${OPENSBI_COMPILER}gcc $(eval env PATH="$toolchain:$PATH" "${OPENSBI_COMPILER}gcc" -dumpfullversion -dumpversion)" "info"

	# Patch handling
	local target_make target_patchdir target_files
	# shellcheck disable=SC2034 # Unsure if we need that or not
	target_make="$(cut -d';' -f1 <<< "$OPENSBI_TARGET_MAP")"
	target_patchdir="$(cut -d';' -f2 <<< "$OPENSBI_TARGET_MAP")"
	target_files="$(cut -d';' -f3 <<< "$OPENSBI_TARGET_MAP")"

	advanced_patch "opensbi" "${OPENSBIPATCHDIR}" "$BOARD" "$target_patchdir" "$BRANCH" "${LINUXFAMILY}-${BOARD}-${BRANCH}"

	# create patch for manual source changes
	[ "$CREATE_PATCHES_OPENSBI" != yes ] || {
		userpatch_create "openbsi"
		return 0
	}

	# Perform compilation
	# @FIXME: Should we integrate '$target_make' here?
	run_host_command_logged \
		CCACHE_BASEDIR="$(pwd)" \
		PATH="$toolchain:$PATH" \
		make \
			BUILD_STRING="armbian" \
			PLATFORM=generic \
			FW_PIC=y \
			"CROSS_COMPILE='$CCACHE $OPENSBI_COMPILER'"

	[[ "${PIPESTATUS[0]}" -ne 0 ]] && exit_with_error "opensbi compilation failed"

	# Apply post-process
	## @TODO: severely missing logging
	[ "$(type -t opensbi_custom_postprocess)" != function ] || opensbi_custom_postprocess  2>&1

	# Finalize
	opensbitempdir="$(mktemp -d)" # subject to TMPDIR/WORKDIR, so is protected by single/common error trapmanager to clean-up
	chmod 700 "${opensbitempdir}"

	# copy files to temp directory
	for f in $target_files; do
		local f_src
		f_src="$(cut -d':' -f1 <<< "$f")"

		case "$f" in
			*:*)
				local f_dst
				f_dst="$(cut -d':' -f2 <<< "$f")"
				;;
			*)
				local f_dst
				f_dst="$(basename "$f_src")"
		esac

		[ -f "$f_src" ] || exit_with_error "OPENSBI file not found" "$(basename "$f_src")"

		cp -v "$f_src" "$opensbitempdir/$f_dst"
	done

	# copy license file to pack it to u-boot package later
	[ ! -f license.md ] || cp -v license.md "$opensbitempdir/"

	return 0 # avoid error due to short-circuit above
}
