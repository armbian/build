#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
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
	declare image_file="${IMAGE:-""}"
	# If not set, find the latest .img file in ${SRC}/output/images/
	if [[ -z "${image_file}" ]]; then
		# shellcheck disable=SC2012
		image_file="$(ls -1t "${SRC}/output/images"/*"${BOARD^}_${RELEASE}_${BRANCH}"*.img | head -1)"
		display_alert "cli_flash" "No image file specified. Using latest built image file found: ${image_file}" "info"
	fi
	if [[ ! -f "${image_file}" ]]; then
		exit_with_error "No image file to flash."
	fi
	declare image_file_basename
	image_file_basename="$(basename "${image_file}")"
	display_alert "cli_flash" "Flashing image file: ${image_file_basename}" "info"
	countdown_and_continue_if_not_aborted 3

	write_image_to_device_and_run_hooks "${image_file}"
}
