#!/bin/bash
#
# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# exit_with_error <message> <highlight>
#
# a way to terminate build process
# with verbose error message
#

function exit_with_error() {
	local _file
	local _line=${BASH_LINENO[0]}
	local _function=${FUNCNAME[1]}
	local _description=$1
	local _highlight=$2
	_file=$(basename "${BASH_SOURCE[1]}")
	local stacktrace logfile
	stacktrace="$(get_extension_hook_stracktrace "${BASH_SOURCE[*]}" "${BASH_LINENO[*]}" || true)"

	local logfile_to_show="${CURRENT_LOGFILE}" # store it
	unset CURRENT_LOGFILE                      # stop logging, otherwise crazy

	display_alert "ERROR in function $_function" "$stacktrace" "err"
	display_alert "$_description" "$_highlight" "err"

	# delegate to logging to make it pretty
	logging_error_show_log "$_description" "$_highlight" "${stacktrace}" "${logfile_to_show}"

	if [[ "${ERROR_DEBUG_SHELL}" == "yes" ]]; then
		display_alert "MOUNT" "${MOUNT}" "err"
		display_alert "SDCARD" "${SDCARD}" "err"
		display_alert "Here's a shell." "debug it" "err"
		bash < /dev/tty || true
	fi

	display_alert "Build terminating... wait for cleanups..." "" "err"

	overlayfs_wrapper "cleanup"
	# unlock loop device access in case of starvation # @TODO: hmm, say that again?
	exec {FD}> /var/lock/armbian-debootstrap-losetup
	flock -u "${FD}"

	export ALREADY_EXITING_WITH_ERROR=yes # marker for future trap handlers. avoid showing errors twice.
	exit 43
	display_alert "Never to be seen" "after exit and traps" "bye"
}
