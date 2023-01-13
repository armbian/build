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
	declare -g -i logging_section_counter=0                 # -i: integer
	declare -g tool_color="${gray_color}"                   # default to gray... (should be ok on terminals, @TODO: I've seen it too dark on a few random screenshots though
	if [[ "${CI}" == "true" ]]; then                        # ... but that is too dark for Github Actions
		declare -g tool_color="${normal_color}"
		declare -g SHOW_LOG="${SHOW_LOG:-"yes"}" # if in CI/GHA, default to showing log
	fi
	if [[ "${ARMBIAN_RUNNING_IN_CONTAINER}" == "yes" ]]; then # if in container, add a cyan "whale emoji" to the left marker wrapped in dark gray brackets
		local container_emoji="🐳"                                #  🐳 or 🐋
		declare -g left_marker="${gray_color}[${container_emoji}|${normal_color}"
	elif [[ "$(uname -s)" == "Darwin" ]]; then # if on Mac, add a an apple emoji to the left marker wrapped in dark gray brackets
		local mac_emoji="🍏"                       # 🍏 or 🍎
		declare -g left_marker="${gray_color}[${mac_emoji}|${normal_color}"
	fi
}

function logging_error_show_log() {
	local logfile_to_show="${CURRENT_LOGFILE}" # store current logfile in separate var
	unset CURRENT_LOGFILE                      # stop logging, otherwise crazy
	[[ "${SHOW_LOG}" == "yes" ]] && return 0   # Do nothing if we're already showing the log on stderr.
	if [[ "${CI}" == "true" ]]; then           # Close opened CI group, even if there is none; errors would be buried otherwise.
		echo "::endgroup::"
	fi

	if [[ -f "${logfile_to_show}" ]]; then
		local prefix_sed_contents="${normal_color}${left_marker}${padding}👉${padding}${right_marker}    "
		local prefix_sed_cmd="s/^/${prefix_sed_contents}/;"
		display_alert "    👇👇👇 Showing logfile below 👇👇👇" "${logfile_to_show}" "err"

		# shellcheck disable=SC2002 # my cat is great. thank you, shellcheck.
		cat "${logfile_to_show}" | grep -v -e "^$" | sed -e "${prefix_sed_cmd}" 1>&2 # write it to stderr!!

		display_alert "    👆👆👆 Showing logfile above 👆👆👆" "${logfile_to_show}" "err"
	else
		display_alert "✋ Error log not available at this stage of build" "check messages above" "debug"
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

function discard_logs_tmp_dir() {
	# Linux allows us to be more careful, but really, those are log files we're talking about.
	if [[ "$(uname)" == "Linux" ]]; then
		rm -rf --one-file-system "${LOGDIR}"
	else
		rm -rf "${LOGDIR}"
	fi
}
