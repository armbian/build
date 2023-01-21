#!/usr/bin/env bash

# This is called both early in compile.sh, but also after processing cmdline params in the cli entrypoint.sh
function logging_init() {
	# defaults.
	# if stdout is a terminal, then default SHOW_LOG to yes
	[[ -t 1 ]] && declare -g SHOW_LOG="${SHOW_LOG:-"yes"}"

	# if DEBUG=yes, is set then default both log & debug to yes
	if [[ "${DEBUG}" == "yes" ]]; then
		declare -g SHOW_LOG="${SHOW_LOG:-"yes"}"
		declare -g SHOW_DEBUG="${SHOW_DEBUG:-"yes"}"
	fi

	# globals
	declare -g padding="" left_marker="[" right_marker="]"
	declare -g normal_color="\x1B[0m" gray_color="\e[1;30m" # "bright black", which is grey
	declare -g bright_red_color="\e[1;31m" red_color="\e[0;31m"
	declare -g bright_blue_color="\e[1;34m" blue_color="\e[0;34m"
	declare -g bright_magenta_color="\e[1;35m" magenta_color="\e[0;35m"
	declare -g ansi_reset_color="\e[0m"
	declare -g -i logging_section_counter=0 # -i: integer
	declare -g tool_color="${gray_color}"   # default to gray... (should be ok on terminals, @TODO: I've seen it too dark on a few random screenshots though
	if [[ "${CI}" == "true" ]]; then        # ... but that is too dark for Github Actions
		declare -g tool_color="${normal_color}"
		declare -g SHOW_LOG="${SHOW_LOG:-"yes"}" # if in CI/GHA, default to showing log
	fi
	if [[ "${ARMBIAN_RUNNING_IN_CONTAINER}" == "yes" ]]; then # if in container, add a cyan "whale emoji" to the left marker wrapped in dark gray brackets
		local container_emoji="🐳"                                #  🐳 or 🐋
		declare -g left_marker="${gray_color}[${container_emoji}|${normal_color}"
	elif [[ "$(uname -s)" == "Darwin" ]]; then # if on Mac, add a an apple emoji to the left marker wrapped in dark gray brackets
		local mac_emoji="🍏"                       # 🍏 or 🍎
		declare -g left_marker="${gray_color}[${mac_emoji}|${normal_color}"
	else
		declare wsl2_type
		wsl2_detect_type
		if [[ "${wsl2_type}" != "none" ]]; then
			local windows_emoji="💲" # 💰 or 💲 for M$ -- get it?
			declare -g left_marker="${gray_color}[${windows_emoji}|${normal_color}"
		fi
	fi
}

function logging_error_show_log() {
	[[ "${SHOW_LOG}" == "yes" ]] && return 0 # Do nothing if we're already showing the log on stderr.
	# Do NOT unset CURRENT_LOGFILE here... it's used by traps.

	local logfile_to_show="${CURRENT_LOGFILE}" # store current logfile in separate var
	if [[ "${CI}" == "true" ]]; then           # Close opened CI group, even if there is none; errors would be buried otherwise.
		echo "::endgroup::"
	fi

	if [[ -f "${logfile_to_show}" ]]; then
		local prefix_sed_contents="${normal_color}${left_marker}${padding}👉${padding}${right_marker}    "
		local prefix_sed_cmd="s/^/${prefix_sed_contents}/;"
		CURRENT_LOGFILE="" display_alert "    👇👇👇 Showing logfile below 👇👇👇" "${logfile_to_show}" "err"

		# shellcheck disable=SC2002 # my cat is great. thank you, shellcheck.
		cat "${logfile_to_show}" | grep -v -e "^$" | sed -e "${prefix_sed_cmd}" 1>&2 # write it to stderr!!

		CURRENT_LOGFILE="" display_alert "    👆👆👆 Showing logfile above 👆👆👆" "${logfile_to_show}" "err"
	else
		CURRENT_LOGFILE="" display_alert "✋ Error log not available at this stage of build" "check messages above" "debug"
	fi
	return 0
}

# usage example:
# declare -a verbose_params=() && if_user_on_terminal_and_not_logging_add verbose_params "--verbose" "--progress"
# echo "here is the verbose params: ${verbose_params[*]}"
function if_user_on_terminal_and_not_logging_add() {
	# Is user on a terminal? if not, do nothing.
	if [[ ! -t 1 ]]; then
		return 0
	fi
	# are we running under a logging section? if so, do nothing.
	if [[ -n "${CURRENT_LOGGING_SECTION}" ]]; then
		return 0
	fi
	# If we're here, we're on a terminal and not logging.
	declare -n _add_to="$1" # nameref to an array; can't use '-a' here
	shift
	_add_to+=("$@")
	return 0
}

function if_user_not_on_terminal_or_is_logging_add() {
	# Is user on a terminal? if yes, do nothing.
	if [[ -t 1 ]]; then
		return 0
	fi
	# are we running under a logging section? if not, do nothing.
	if [[ -z "${CURRENT_LOGGING_SECTION}" ]]; then
		return 0
	fi
	declare -n _add_to_inverse="$1" # nameref to an array; can't use '-a' here
	shift
	_add_to_inverse+=("$@")
	return 0
}

# This takes LOG_ASSET, which can and should include an extension.
function do_with_log_asset() {
	# @TODO: check that CURRENT_LOGGING_COUNTER is set, otherwise crazy?
	local ASSET_LOGFILE="${CURRENT_LOGGING_DIR}/${CURRENT_LOGGING_COUNTER}.${LOG_ASSET}"
	display_alert "Logging to asset" "${CURRENT_LOGGING_COUNTER}.${LOG_ASSET}" "debug"
	"$@" >> "${ASSET_LOGFILE}"
}

function print_current_asset_log_base_file() {
	declare ASSET_LOGFILE_BASE="${CURRENT_LOGGING_DIR}/${CURRENT_LOGGING_COUNTER}."
	echo -n "${ASSET_LOGFILE_BASE}"
}

function check_and_close_fd_13() {
	wait_for_disk_sync "before closing fd 13" # let the disk catch up
	if [[ -e /proc/self/fd/13 ]]; then
		display_alert "Closing fd 13" "log still open" "cleanup" # no reason to be alarmed
		exec 13>&- || true                                       # close the file descriptor, lest sed keeps running forever.
		wait_for_disk_sync "after fd 13 closure"                 # make sure the file is written to disk
	else
		display_alert "Not closing fd 13" "log already closed" "cleanup"
	fi

	# "tee_pid" is a misnomer: it in reality is a shell pid with tee and sed children.
	display_alert "Checking if global_tee_pid is set and running" "global_tee_pid: ${global_tee_pid}" "cleanup"
	if [[ -n "${global_tee_pid}" && ${global_tee_pid} -gt 1 ]] && ps -p "${global_tee_pid}" > /dev/null; then
		display_alert "Killing global_tee_pid's children" "global_tee_pid: ${global_tee_pid}" "cleanup"

		declare -a descendants_of_pid_array_result=()
		get_descendants_of_pid_array "${global_tee_pid}" || true
		# loop over descendants_of_pid_array_result and kill'em'all
		for descendant_pid in "${descendants_of_pid_array_result[@]}"; do
			# check if PID is still alive before killing; it might have died already due to death of parent.
			if ps -p "${descendant_pid}" > /dev/null; then
				display_alert "Killing descendant pid" "${descendant_pid}" "cleanup"
				{ kill "${descendant_pid}" && wait "${global_tee_pid}"; } || true
			else
				display_alert "Descendant PID already dead" "${descendant_pid}" "cleanup"
			fi
		done

		# If the global_tee_pid is still alive, kill it.
		if ps -p "${global_tee_pid}" > /dev/null; then
			display_alert "Killing global_tee_pid" "${global_tee_pid}" "cleanup"
			kill "${global_tee_pid}" && wait "${global_tee_pid}"
		else
			display_alert "global_tee_pid already dead after descendants killed" "${global_tee_pid}" "cleanup"
		fi
		wait_for_disk_sync "after killing tee pid" # wait for the disk to catch up
	else
		display_alert "Not killing global_tee_pid" "${global_tee_pid} not running" "cleanup"
	fi
}

function discard_logs_tmp_dir() {
	# if we're in a logging section and logging to file when an error happened, and we're now cleaning up,
	# the "tee" process created for fd 13 in do_with_logging() is still running, and holding a reference to the log file,
	# which resides precisely in LOGDIR. So we need to kill it.

	# Check if fd 13 is still open; close it and wait for tee to die.
	check_and_close_fd_13

	# Do not delete the dir itself, since it might be a tmpfs mount.
	if [[ "$(uname)" == "Linux" ]]; then
		rm -rf --one-file-system "${LOGDIR:?}"/* # Note this is protected by :?
	else
		rm -rf "${LOGDIR:?}"/* # Note this is protected by :?
	fi
}
