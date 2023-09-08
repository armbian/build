#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2023 Jacob Hrbek, kreyren@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

compile_opensbi() {
	case "$OPENSBISOURCE" in
		""|"none") true	;;
		*)
			display_alert "Downloading sources" "opensbi" "git"
			fetch_from_repo "$OPENSBISOURCE" "$OPENSBIDIR" "$OPENSBIBRANCH" "yes"
	esac

	# Clean
	case "$CLEAN_LEVEL" in *make-opensbi*)
		display_alert "Cleaning" "$OPENSBISOURCEDIR" "info"
		(
			cd "${SRC}/cache/sources/$OPENSBISOURCEDIR" || exit_with_error "crazy about $OPENSBISOURCEDIR"
			run_host_command_logged make distclean
		)
	esac

	# Handle overlays
	case "$USE_OVERLAYFS" in
		"yes")
			local opensbidir="$(overlayfs_wrapper "wrap" "$SRC/cache/sources/$OPENSBISOURCEDIR" "opensbi_${LINUXFAMILY}_${BRANCH}")"
			;;
		*)
			local opensbidir="$SRC/cache/sources/$OPENSBISOURCEDIR"
	esac

	cd "$opensbidir" || exit

	display_alert "Compiling OpenSBI" "" "info"

	# build riscv64
	systemarch="$(dpkg --print-architecture)"
	case "$systemarch" in
		"amd64")
			local toolchain="$(find_toolchain "$OPENSBI_COMPILER" "$OPENSBI_USE_GCC")"

			[ -n $toolchain ] || exit_with_error "Could not find required toolchain" "${OPENSBI_COMPILER}gcc $OPENSBI_USE_GCC"
			;;
		*) exit_with_error "This architecture '$systemarch' is not implemented to build OpenSBI for board '$BOARD', fixme?"
	esac

	# FIXME-SECURITY(Krey): Eval is dangerous, rewrite to avoid using it or sanitize
	display_alert "Compiler version" "${OPENSBI_COMPILER}gcc $(eval env PATH="$toolchain:$PATH" "${OPENSBI_COMPILER}gcc" -dumpfullversion -dumpversion)" "info"

	# Patch handling
	local target_make target_patchdir target_files
	target_make="$(cut -d';' -f1 <<< "$OPENSBI_TARGET_MAP")"
	target_patchdir="$(cut -d';' -f2 <<< "$OPENSBI_TARGET_MAP")"
	target_files="$(cut -d';' -f3 <<< "$OPENSBI_TARGET_MAP")"

	advanced_patch "opensbi" "$OPENSBIPATCHDIR" "$BOARD" "$target_patchdir" "$BRANCH" "$LINUXFAMILY-$BOARD-$BRANCH"

	# create patch for manual source changes
	[ "$CREATE_PATCHES_OPENSBI" != yes ] || {
		userpatch_create "openbsi"
		return 0
	}

	# Perform compilation
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
	chmod 700 "$opensbitempdir"

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
