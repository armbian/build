#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function cli_flash_pre_run() {
	display_alert "cli_distccd_pre_run" "func cli_distccd_run :: ${ARMBIAN_COMMAND}" "warn"

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function cli_flash_run() {
	if [[ -n "${BOARD}" ]]; then
		use_board="yes" prep_conf_main_minimal_ni < /dev/null # no stdin for this, so it bombs if tries to be interactive.
	else
		use_board="no" prep_conf_main_minimal_ni < /dev/null # no stdin for this, so it bombs if tries to be interactive.
	fi

	# the full build. It has its own logging sections.
	do_with_default_build cli_flash
}

function cli_flash() {
	# Without a target device there is nothing downstream to catch it:
	# write_image_to_device's `lsblk "${device}"` test is false for an empty
	# device, and its in-container branch needs a non-empty device too, so the
	# write is skipped and `flash` exits 0 having done nothing at all -- after
	# announcing the image and counting down, which reads as success.
	# Docker is not the obstacle: the launcher passes CARD_DEVICE into the
	# container when it is set.
	if [[ -z "${CARD_DEVICE:-}" ]]; then
		exit_with_error "No target device to flash to" \
			"pass CARD_DEVICE=/dev/sdX (see 'lsblk' for the device name)"
	fi
	if [[ ! -b "${CARD_DEVICE}" ]]; then
		exit_with_error "CARD_DEVICE is not a block device" "${CARD_DEVICE}"
	fi

	declare image_file="${IMAGE:-""}"

	# If not set, find the most recent .img in ${SRC}/output/images/, narrowed by
	# whichever of BOARD/RELEASE/BRANCH this invocation actually set.
	#
	# Composing one glob out of all three unconditionally collapses it to
	# '*__*.img' when none is set, which is what a bare './compile.sh flash'
	# does. That matches no Armbian image -- they are named
	# <version>_<Board>_<release>_<branch>_... -- so the command failed with a
	# raw "ls: cannot access" even when output/images held a perfectly good
	# image. Filter the listing instead of building a pattern from empty parts.
	if [[ -z "${image_file}" ]]; then
		declare -a images=()
		declare candidate token
		# Newest first. find, not a glob, so a missing or empty directory gives
		# an empty list rather than an unexpanded pattern on stderr.
		while read -r candidate; do
			images+=("${candidate}")
		done < <(find "${SRC}/output/images" -maxdepth 1 -type f -name '*.img' -printf '%T@\t%p\n' 2> /dev/null | sort -rn | cut -f2-)

		declare board_token="${BOARD:+${BOARD^}}"
		for token in "${board_token}" "${RELEASE}" "${BRANCH}"; do
			if [[ -z "${token}" ]]; then
				continue
			fi
			declare -a kept=()
			for candidate in "${images[@]}"; do
				# Match the selector as a complete underscore-delimited field, not
				# a loose substring: image names are
				# VENDOR_VERSION_Board_release_branch_kver..., where Board/release/
				# branch are all middle fields, so a short release/branch (e.g.
				# 'sid', 'edge') can't accidentally match inside another field.
				if [[ "${candidate##*/}" == *"_${token}_"* ]]; then
					kept+=("${candidate}")
				fi
			done
			images=("${kept[@]}")
		done

		if [[ ${#images[@]} -eq 0 ]]; then
			exit_with_error "No image found in ${SRC}/output/images to flash" \
				"build one first, or pass IMAGE=/path/to/image.img"
		fi

		image_file="${images[0]}"
		display_alert "cli_flash" "No image file specified. Using latest built image file found: ${image_file##*/}" "info"
	fi
	if [[ ! -f "${image_file}" ]]; then
		exit_with_error "No image file to flash" "${image_file}"
	fi
	declare image_file_basename
	image_file_basename="$(basename "${image_file}")"
	display_alert "cli_flash" "Flashing image file: ${image_file_basename}" "info"
	countdown_and_continue_if_not_aborted 3

	write_image_to_device_and_run_hooks "${image_file}"
}
