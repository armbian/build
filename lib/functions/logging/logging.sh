#!/usr/bin/env bash

function logging_init() {
	# globals
	export padding="" left_marker="[" right_marker="]"
	export normal_color="\x1B[0m" gray_color="\e[1;30m" # "bright black", which is grey
}

function logging_error_show_log() {
	# Do nothing if we're already showing the log on stderr.
	[[ "${SHOW_LOG}" == "yes" ]] && return 0

	# Close opened CI group, even if there is none; errors would be buried otherwise.
	if [[ "${CI}" == "true" ]]; then
		echo "::endgroup::"
	fi

	local message="$1"
	local stacktrace="$3"
	local logfile_to_show="$4"

	if [[ -f "${logfile_to_show}" ]]; then

		local prefix_sed_contents="${normal_color}${left_marker}${padding}👉${padding}${right_marker}    "
		local prefix_sed_cmd="s/^/${prefix_sed_contents}/;"
		display_alert "    👇👇👇 Showing logfile below 👇👇👇" "${logfile_to_show}" "err"
		# shellcheck disable=SC2002 # my cat is great. thank you, shellcheck.
		cat "${logfile_to_show}" | grep -v -e "^$" | sed -e "${prefix_sed_cmd}" 1>&2 # write it to stderr!!
		display_alert "    👆👆👆 Showing logfile above 👆👆👆" "${logfile_to_show}" "err"
		display_alert "🦞 Error Msg" "$message" "err"
		display_alert "🐞 Error stacktrace" "$stacktrace" "err"
	else
		display_alert "✋ Error Log not Available" "${logfile_to_show}" "err"
	fi
	return 0
}

function do_with_logging() {
	[[ -z "${DEST}" ]] && exit_with_error "DEST is not defined. Can't start logging."

	# @TODO: check we're not currently logging (eg: this has been called 2 times without exiting)
	export CURRENT_LOGGING_SECTION=${LOG_SECTION:-build}
	export CURRENT_LOGGING_DIR="${DEST}/${LOG_SUBPATH}"
	export CURRENT_LOGFILE="${CURRENT_LOGGING_DIR}/000.${CURRENT_LOGGING_SECTION}.log"
	mkdir -p "${CURRENT_LOGGING_DIR}"

	# Markers for CI (GitHub Actions); CI env var comes predefined as true there.
	if [[ "${CI}" == "true" ]]; then
		echo "::group::[🥑] Group ${CURRENT_LOGGING_SECTION}"
	fi

	# We now execute whatever was passed as parameters, in some different conditions:
	# In both cases, writing to stderr will display to terminal.
	# So whatever is being called, should prevent rogue stuff writing to stderr.
	# this is mostly handled by redirecting stderr to stdout: 2>&1

	local exit_code=176 # fail by default...
	if [[ "${SHOW_LOG}" == "yes" ]]; then
		local prefix_sed_contents
		local tool_color="${gray_color}" # default to gray... (should be ok on terminals)
		if [[ "${CI}" == "true" ]]; then # ... but that is too dark for Github Actions
			tool_color="${normal_color}"
		fi
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
		exit_code=$? # hopefully this is the pipe
		exec 3>&-    # close the file descriptor, lest sed keeps running forever.
	else
		# If not showing the log, just send stdout to logfile. stderr will flow to screen.
		"$@" >> "${CURRENT_LOGFILE}"
		exit_code=$?
	fi

	# Close opened CI group.
	if [[ "${CI}" == "true" ]]; then
		echo "::endgroup::"
	fi

	if [[ $exit_code != 0 ]]; then
		display_alert "build group FAILED: exit code: ${exit_code}" "${CURRENT_LOGGING_SECTION}" "err"
	fi

	return $exit_code
}

display_alert() {
	# We'll be writing to stderr (" >&2"), so also write the message to the generic logfile, for context.
	if [[ -f "${CURRENT_LOGFILE}" ]]; then
		echo "--> A: [" "$@" "]" >> "${CURRENT_LOGFILE}"
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
			level_indicator="🌱" # "🌴" 🥑
			inline_logs_color="\e[0;32m"
			;;

		debug | deprecation)
			level_indicator="✨" # "🌴" 🥑
			inline_logs_color="\e[1;33m"
			;;

		*)
			level_indicator="🌿" #  "✨" 🌿 🪵
			inline_logs_color="\e[1;37m"
			;;
	esac
	[[ -n $2 ]] && extra=" [${inline_logs_color} ${2} ${normal_color}]"
	echo -e "${normal_color}${left_marker}${padding}${level_indicator}${padding}${normal_color}${right_marker} ${normal_color}${message}${extra}${normal_color}" >&2

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
