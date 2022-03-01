#!/usr/bin/env bash

function logging_init() {
	# globals
	export padding="" left_marker="[" right_marker="]"
	export normal_color="\x1B[0m" gray_color="\e[1;30m" # "bright black", which is grey
	declare -i logging_section_counter=0                # -i: integer
	export logging_section_counter
	export tool_color="${gray_color}" # default to gray... (should be ok on terminals)
	if [[ "${CI}" == "true" ]]; then  # ... but that is too dark for Github Actions
		export tool_color="${normal_color}"
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

		if [[ -f /usr/bin/ccze ]]; then # use 'ccze' to colorize the log, making errors a lot more obvious.
			# shellcheck disable=SC2002 # my cat is great. thank you, shellcheck.
			cat "${logfile_to_show}" | grep -v -e "^$" | /usr/bin/ccze -A | sed -e "${prefix_sed_cmd}" 1>&2 # write it to stderr!!
		else
			# shellcheck disable=SC2002 # my cat is great. thank you, shellcheck.
			cat "${logfile_to_show}" | grep -v -e "^$" | sed -e "${prefix_sed_cmd}" 1>&2 # write it to stderr!!
		fi

		display_alert "    👆👆👆 Showing logfile above 👆👆👆" "${logfile_to_show}" "err"
	else
		display_alert "✋ Error log not available at this stage of build" "check messages above" "debug"
	fi
	return 0
}

function start_logging_section() {
	export logging_section_counter=$((logging_section_counter + 1)) # increment counter, used in filename
	export CURRENT_LOGGING_COUNTER
	CURRENT_LOGGING_COUNTER="$(printf "%03d" "$logging_section_counter")"
	export CURRENT_LOGGING_SECTION=${LOG_SECTION:-early} # default to "early", should be overwritten soon enough
	export CURRENT_LOGGING_DIR="${LOGDIR}"               # set in cli-entrypoint.sh
	export CURRENT_LOGFILE="${CURRENT_LOGGING_DIR}/${CURRENT_LOGGING_COUNTER}.${CURRENT_LOGGING_SECTION}.log"
	mkdir -p "${CURRENT_LOGGING_DIR}"
	touch "${CURRENT_LOGFILE}" # Touch it, make sure it's writable.

	# Markers for CI (GitHub Actions); CI env var comes predefined as true there.
	if [[ "${CI}" == "true" ]]; then # On CI, this has special meaning.
		echo "::group::[🥑] Group ${CURRENT_LOGGING_SECTION}"
	else
		display_alert "start group" "<${CURRENT_LOGGING_SECTION}>" "group"
	fi
	return 0
}

function finish_logging_section() {
	# Close opened CI group.
	if [[ "${CI}" == "true" ]]; then
		echo "::endgroup::"
	else
		display_alert "finish group" "</${CURRENT_LOGGING_SECTION}>" "group"
	fi
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

	if [[ "${SHOW_LOG}" == "yes" ]]; then
		local prefix_sed_contents
		prefix_sed_contents="$(logging_echo_prefix_for_pv "tool")   $(echo -n -e "${tool_color}")"
		local prefix_sed_cmd="s/^/${prefix_sed_contents}/;"

		# This is sick. Create a 3rd file descriptor sending it to sed. https://unix.stackexchange.com/questions/174849/redirecting-stdout-to-terminal-and-file-without-using-a-pipe
		# Also terrible: don't hold a reference to cwd by changing to SRC always
		exec 3> >(
			cd "${SRC}" || exit 2
			#grep --line-buffered -v "^$" | \
			sed -u -e "${prefix_sed_cmd}"
		)
		"$@" >&3
		exec 3>&- # close the file descriptor, lest sed keeps running forever.
	else
		# If not showing the log, just send stdout to logfile. stderr will flow to screen.
		"$@" >> "${CURRENT_LOGFILE}"
	fi

	finish_logging_section

	return 0
}

function display_alert() {
	# We'll be writing to stderr (" >&2"), so also write the message to the generic logfile, for context.
	if [[ -f "${CURRENT_LOGFILE}" ]]; then
		echo -e "--> A: [" "$@" "]" | sed 's/\x1b\[[0-9;]*m//g' >> "${CURRENT_LOGFILE}"
	fi

	# If asked, avoid any fancy ANSI escapes completely.
	if [[ "${ANSI_COLOR}" == "none" ]]; then
		echo -e "${@}" | sed 's/\x1b\[[0-9;]*m//g' >&2
		return 0
	fi

	local message="$1" level="$3"                                    # params
	local level_indicator="" inline_logs_color="" extra="" ci_log="" # this log
	case "${level}" in
		err | error)
			level_indicator="💥"
			inline_logs_color="\e[1;31m"
			ci_log="error"
			;;

		wrn | warn)
			level_indicator="🚸"
			inline_logs_color="\e[1;35m"
			ci_log="warning"
			;;

		ext)
			level_indicator="✅"
			inline_logs_color="\e[1;32m"
			ci_log="notice"
			;;

		info)
			level_indicator="🌱"
			inline_logs_color="\e[0;32m"
			;;

		cleanup | trap)
			if [[ "${SHOW_TRAPS}" != "yes" ]]; then # enable debug for many, many debugging msgs
				return 0
			fi
			level_indicator="🧽"
			inline_logs_color="\e[1;33m"
			;;

		debug | deprecation)
			if [[ "${SHOW_DEBUG}" != "yes" ]]; then # enable debug for many, many debugging msgs
				return 0
			fi
			level_indicator="✨"
			inline_logs_color="\e[1;33m"
			;;

		group)
			if [[ "${SHOW_DEBUG}" != "yes" && "${SHOW_GROUPS}" != "yes" ]]; then # show when debugging, or when specifically requested
				return 0
			fi
			level_indicator="🦋"
			inline_logs_color="\e[1;36m" # cyan
			;;

		command)
			if [[ "${SHOW_COMMAND}" != "yes" ]]; then # enable to log all calls to external cmds
				return 0
			fi
			level_indicator="🐸"
			inline_logs_color="${tool_color}" # either gray or normal, a bit subdued.
			;;

		*)
			level_indicator="🌿"
			inline_logs_color="\e[1;37m"
			;;
	esac

	local timing_info=""
	if [[ "${SHOW_TIMING}" == "yes" ]]; then
		timing_info="${tool_color}(${normal_color}$(printf "%3s" "${SECONDS}")${tool_color})" # SECONDS is bash builtin for seconds since start of script.
	fi

	local pids_info=""
	if [[ "${SHOW_PIDS}" == "yes" ]]; then
		pids_info="${tool_color}(${normal_color}$$ - ${BASHPID}${tool_color})" # BASHPID is the current subshell; $$ is parent's?
	fi

	local bashopts_info=""
	if [[ "${SHOW_BASHOPTS}" == "yes" ]]; then
		bashopts_info="${tool_color}(${normal_color}$-${tool_color})" # $- is the currently active bashopts
	fi

	[[ -n $2 ]] && extra=" [${inline_logs_color} ${2} ${normal_color}]"
	echo -e "${normal_color}${left_marker}${padding}${level_indicator}${padding}${normal_color}${right_marker}${timing_info}${pids_info}${bashopts_info} ${normal_color}${message}${extra}${normal_color}" >&2

	# Now write to CI, if we're running on it
	if [[ "${CI}" == "true" ]] && [[ "${ci_log}" != "" ]]; then
		echo "::${ci_log} ::" "$@" >&2
	fi

	return 0 # make sure to exit with success, always
}

function logging_echo_prefix_for_pv() {
	local what="$1"
	local indicator="🤓" # you guess who this is
	case $what in
		extract_rootfs)
			indicator="💖"
			;;
		tool)
			indicator="🔨"
			;;
		compile)
			indicator="🐴"
			;;
		write_device)
			indicator="💾"
			;;
		create_rootfs_archive | decompress | compress_kernel_sources)
			indicator="🤐"
			;;
	esac

	echo -n -e "${normal_color}${left_marker}${padding}${indicator}${padding}${normal_color}${right_marker}"
	return 0

}
