#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function start_logging_section() {
	# Sanity check: if this is called, but CURRENT_LOGGING_SECTION is not empty, then something is wrong.
	if [[ -n "${CURRENT_LOGGING_SECTION}" && "${CURRENT_LOGGING_SECTION}" != "entrypoint" ]]; then
		exit_with_error "ERROR: start_logging_section() called, but CURRENT_LOGGING_SECTION is not empty: current: '${CURRENT_LOGGING_SECTION}' trying to enter '${LOG_SECTION}'"
		return 1
	fi

	declare -g logging_section_counter=$((logging_section_counter + 1)) # increment counter, used in filename
	declare -g CURRENT_LOGGING_COUNTER
	CURRENT_LOGGING_COUNTER="$(printf "%03d" "$logging_section_counter")"
	declare -g CURRENT_LOGGING_SECTION=${LOG_SECTION:-early} # default to "early", should be overwritten soon enough
	declare -g CURRENT_LOGGING_SECTION_START=${SECONDS}
	declare -g CURRENT_LOGGING_DIR="${LOGDIR}" # set in cli-entrypoint.sh
	declare -g CURRENT_LOGFILE="${CURRENT_LOGGING_DIR}/${CURRENT_LOGGING_COUNTER}.000.${CURRENT_LOGGING_SECTION}.log"
	mkdir -p "${CURRENT_LOGGING_DIR}"
	touch "${CURRENT_LOGFILE}" # Touch it, make sure it's writable.

	# Markers for CI (GitHub Actions); CI env var comes predefined as true there.
	if [[ "${CI}" == "true" ]]; then # On CI, this has special meaning.
		echo "::group::[🥑] Group ${CURRENT_LOGGING_SECTION}"
	else
		display_alert "" "<${CURRENT_LOGGING_SECTION}>" "group"
	fi
	return 0
}

function finish_logging_section() {
	# Close opened CI group.
	if [[ "${CI}" == "true" ]]; then
		echo "Section '${CURRENT_LOGGING_SECTION}' took $((SECONDS - CURRENT_LOGGING_SECTION_START))s to execute." 1>&2 # write directly to stderr
		echo "::endgroup::"
	else
		display_alert "" "</${CURRENT_LOGGING_SECTION}> in $((SECONDS - CURRENT_LOGGING_SECTION_START))s" "group"
	fi
	unset CURRENT_LOGGING_SECTION # clear this var, so we can detect if we're in a section or not later.
}

function do_with_logging() {
	[[ -z "${DEST}" ]] && exit_with_error "DEST is not defined. Can't start logging."

	# @TODO: check we're not currently logging (eg: this has been called 2 times without exiting)

	start_logging_section

	# Important: no error control is done here.
	# Called arguments are run with set -e in effect.

	# We now execute whatever was passed as parameters, in some different conditions:
	# In both cases, writing to stderr will display to terminal.
	# So whatever is being called, should prevent rogue stuff writing to stderr.
	# this is mostly handled by redirecting stderr to stdout: 2>&1

	# global var to store the pid of spawned logging process.
	declare -g -i global_tee_pid=0

	if [[ "${SHOW_LOG}" == "yes" ]]; then
		local prefix_sed_contents
		prefix_sed_contents="$(logging_echo_prefix_for_pv "tool")   $(echo -n -e "${tool_color}")" # spaces are significant
		local prefix_sed_cmd="s/^/${prefix_sed_contents}/;"

		# Create a 13rd file descriptor sending it to sed. https://unix.stackexchange.com/questions/174849/redirecting-stdout-to-terminal-and-file-without-using-a-pipe
		# Also terrible: don't hold a reference to cwd by changing to SRC always
		# There's handling of this fd 13 in check_and_close_fd_13()
		exec 13> >(
			cd "${SRC}" || exit 2
			# First, log to file, then add prefix via sed for what goes to screen.
			tee -a "${CURRENT_LOGFILE}" | sed -u -e "${prefix_sed_cmd}"
		)
		# get the pid of the spawned process, so we can kill it later.
		global_tee_pid=$!

		"$@" >&13
		exec 13>&- # close the file descriptor, lest sed keeps running forever.
	else
		# If not showing the log, just send stdout to logfile. stderr will flow to screen.
		"$@" >> "${CURRENT_LOGFILE}"
	fi

	finish_logging_section

	return 0
}

function do_with_logging_unless_user_terminal() {
	# Is user on a terminal? If so, don't log, just show on screen.
	if [[ -t 1 ]]; then
		display_alert "User is on a terminal, not logging output" "do_with_logging_unless_user_terminal" "debug"
		"$@"
	else
		display_alert "User is not on a terminal, logging output" "do_with_logging_unless_user_terminal" "debug"
		do_with_logging "$@"
	fi
}

function do_with_conditional_logging() {
	# if "do_logging=no", just run the command, otherwise, log it.
	if [[ "${do_logging:-"yes"}" == "no" ]]; then
		display_alert "do_logging=no, not starting logging section" "do_with_conditional_logging" "debug"
		"$@"
	else
		display_alert "normally logging output" "do_with_conditional_logging" "debug"
		do_with_logging "$@"
	fi
}
