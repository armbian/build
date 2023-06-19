#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function github_actions_add_output() {
	# if CI is not GitHub Actions, do nothing
	if [[ "${CI}" != "true" ]] && [[ "${GITHUB_ACTIONS}" != "true" ]]; then
		display_alert "Not running in GitHub Actions, not adding output" "'${*}'" "debug"
		return 0
	fi

	if [[ ! -f "${GITHUB_OUTPUT}" ]]; then
		exit_with_error "GITHUB_OUTPUT file not found '${GITHUB_OUTPUT}'"
	fi

	local output_name="$1"
	shift
	local output_value="$*"

	echo "${output_name}=${output_value}" >> "${GITHUB_OUTPUT}"
	display_alert "Added GHA output" "'${output_name}'='${output_value}'" "ext"
}
