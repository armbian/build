#!/usr/bin/env bash

function logging_error_show_log() {
	local message="$1"
	local context="$2"
	local stacktrace="$3"
	local logfile_to_show="$4"

	if [[ -f "${logfile_to_show}" ]]; then
		local prefix_sed_contents="[👉]   "
		local prefix_sed_cmd="s/^/${prefix_sed_contents}/;"
		display_alert "   👇👇👇 Showing logfile below 👇👇👇" "${logfile_to_show}" "err"
		# shellcheck disable=SC2002 # my cat is great. thank you, shellcheck.
		cat "${logfile_to_show}" | grep -v -e "^$" | sed -e "${prefix_sed_cmd}" 1>&2 # write it TO stderr!!
		display_alert "   👆👆👆 Showing logfile above 👆👆👆" "${logfile_to_show}" "err"
		display_alert "🦞 Error Msg" "$message" "err"
		display_alert "🐞 Error stacktrace" "$stacktrace" "err"
	else
		display_alert "✋ Error Log not Available" "${logfile_to_show}" "err"
	fi
	return 0
}

function do_with_logging() {
	[[ ! -n "${DEST}" ]] && exit_with_error "DEST is not defined. Can't start logging."

	# @TODO: check we're not currently logging (eg: this has been called 2 times without exiting)
	export CURRENT_LOGGING_SECTION=${LOG_SECTION:-build}
	export CURRENT_LOGGING_DIR="${DEST}/${LOG_SUBPATH}"
	export CURRENT_LOGFILE="${CURRENT_LOGGING_DIR}/000.${CURRENT_LOGGING_SECTION}.log"
	mkdir -p "${CURRENT_LOGGING_DIR}"

	# We now execute whatever was passed as parameters, in some different conditions:
	# In both cases, writing to stderr will display to terminal.
	# So whatever is being called, should prevent rogue stuff writing to stderr.
	# this is mostly handled by redirecting stderr to stdout: 2>&1

	local prefix_sed_contents="[🔨]   "
	local prefix_sed_cmd="s/^/${prefix_sed_contents}/;"
	local FAILED=1
	if [[ "${SHOW_LOG}" == "yes" ]]; then
		# This is sick. Create a 3rd file descriptor sending it to sed. https://unix.stackexchange.com/questions/174849/redirecting-stdout-to-terminal-and-file-without-using-a-pipe
		# Also terrible: don't hold a reference to cwd by changing to SRC always
		exec 3> >(
			cd "${SRC}"
			sed -e "${prefix_sed_cmd}"
		)
		{ "$@" && FAILED=0; } >&3
		exec 3>&- # close the file descriptor, lest sed keeps running forever.
	else
		# If not showing the log, just send stdout to logfile. stderr will flow to screen.
		{ "$@" && FAILED=0; } >> "${CURRENT_LOGFILE}"
	fi

	return $FAILED # hopefully not
}

display_alert() {
	# We'll be writing to stderr (" >&2"), so also write the message to the generic logfile, for context.
	if [[ -f "${CURRENT_LOGFILE}" ]]; then
		echo "(=-Armbian-: " "$@" >> "${CURRENT_LOGFILE}"
	fi

	local normal_color="\x1B[0m"                      # const
	local padding="" left_marker="[" right_marker="]" # global.
	local message="$1" level="$3"                     # params
	local level_indicator="" main_color="" extra=""   # this log
	case "${level}" in
		err | error)
			level_indicator="💥"
			main_color="\e[0;31m"
			;;

		wrn | warn)
			level_indicator="🚸"
			main_color="\e[0;35m"
			;;

		ext)
			level_indicator="✅"
			main_color="\e[1;32m"
			;;

		info)
			level_indicator="🌴"
			main_color="\e[0;32m"
			;;

		*)
			level_indicator="✨"
			main_color="\e[0;32m"
			;;
	esac
	[[ -n $2 ]] && extra=" [${main_color}${2}${normal_color}]"

	echo -e "${normal_color}${left_marker}${padding}${level_indicator}${padding}${right_marker} ${normal_color}${message}${extra}${normal_color}" >&2
}
