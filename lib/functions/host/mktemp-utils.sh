#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# Those are convenience helpers for creating sub-dirs, for each usage, in WORKDIR.
# They also setup a cleanup trap, and allow early calling of the cleanup handler.
# Usage:
# declare cleanup_id="" temp_dir=""
# prepare_temp_dir_in_workdir_and_schedule_cleanup "NAME_HERE" cleanup_id temp_dir # namerefs
# # ... do stuff with temp_dir ...
# # at the end:
# done_with_temp_dir "${cleanup_id}"
function prepare_temp_dir_in_workdir_and_schedule_cleanup() {
	declare temp_dir_id="${1}"           # gotta be unique across all concurrent invocations.
	declare -n nameref_cleanup_id="${2}" # nameref
	declare -n nameref_temp_dir="${3}"   # nameref

	# if no WORKDIR set, or not an existing directory, bail with error
	if [[ -z "${WORKDIR}" ]] || [[ ! -d "${WORKDIR}" ]]; then
		exit_with_error "prepare_temp_dir_in_workdir_and_schedule_cleanup: WORKDIR is not set or not a directory: ${temp_dir_id}"
	fi

	nameref_temp_dir="$(mktemp -d)" # subject to TMPDIR/WORKDIR
	display_alert "prepare_temp_dir_in_workdir_and_schedule_cleanup: created temp dir" "${nameref_temp_dir}" "cleanup"

	chmod 700 "${nameref_temp_dir}" # does every usage need this? why?

	# add the cleanup handler
	declare -a cleanup_params=("${temp_dir_id}" "${nameref_temp_dir}")
	nameref_cleanup_id="cleanup_temp_dir_in_workdir ${cleanup_params[*]@Q}"
	display_alert "prepare_temp_dir_in_workdir_and_schedule_cleanup: add cleanup handler" "${nameref_cleanup_id}" "cleanup"
	add_cleanup_handler "${nameref_cleanup_id}"
}

function done_with_temp_dir() {
	declare cleanup_id="${1}"
	# validate
	if [[ -z "${cleanup_id}" ]]; then
		exit_with_error "done_with_temp_dir: cleanup_id (arg 1) is empty"
	fi

	# just de-stack from the trap manager. this will trigger an early cleanup under normal conditions.
	# if something fails _before_ this, then the normal trap manager will take care of it.
	execute_and_remove_cleanup_handler "${cleanup_id}"
}

function cleanup_temp_dir_in_workdir() {
	declare temp_dir_id="${1}"
	declare temp_dir="${2}"

	# if no WORKDIR set, or not an existing directory, bail with error
	if [[ -z "${WORKDIR}" ]] || [[ ! -d "${WORKDIR}" ]]; then
		display_alert "cleanup_temp_dir_in_workdir" "WORKDIR is not set or not a directory: ${temp_dir_id}" "err"
		return 1
	fi

	# if no temp_dir set, or not an existing directory, bail with error
	if [[ -z "${temp_dir}" ]] || [[ ! -d "${temp_dir}" ]]; then
		exit_with_error "cleanup_temp_dir_in_workdir" "temp_dir is not set or not a directory: ${temp_dir_id}" "err"
		return 1
	fi

	# remove the dir if we created it.
	cd "${SRC}" || display_alert "cleanup_temp_dir_in_workdir: cd failed" "${SRC}" "err"
	display_alert "cleanup_temp_dir_in_workdir: removing dir" "${temp_dir}" "cleanup"
	rm -rf "${temp_dir:?}"

	return 0
}
