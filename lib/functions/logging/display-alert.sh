function display_alert() {
	# If asked, avoid any fancy ANSI escapes completely. For python-driven log collection. Formatting could be improved.
	# If used, also does not write to logfile even if it exists.
	if [[ "${ANSI_COLOR}" == "none" ]]; then
		echo -e "${@}" | sed 's/\x1b\[[0-9;]*m//g' >&2
		return 0
	fi

	declare message="${1}" level="${3}"                                              # params
	declare level_indicator="" inline_logs_color="" extra="" extra_file="" ci_log="" # this log
	declare -i skip_screen=0                                                         # setting to 1 will not write to screen
	declare -i skip_logfile=0                                                        # setting to 1 will not write to logfile
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
			level_indicator="✨" # or ✅ ?
			inline_logs_color="\e[1;32m"
			;;

		info)
			level_indicator="🌱"
			inline_logs_color="\e[0;32m"
			;;

		cachehit)
			level_indicator="💖"
			inline_logs_color="\e[0;32m"
			;;

		cleanup | trap)
			if [[ "${SHOW_TRAPS}" != "yes" ]]; then # enable debug for many, many debugging msgs
				skip_screen=1
			fi
			level_indicator="🧽"
			inline_logs_color="\e[1;33m"
			skip_logfile=1
			;;

		debug)
			if [[ "${SHOW_DEBUG}" != "yes" ]]; then # enable debug for many, many debugging msgs
				skip_screen=1
			fi
			level_indicator="🐛"
			inline_logs_color="\e[1;33m"
			skip_logfile=1
			;;

		group)
			if [[ "${SHOW_DEBUG}" != "yes" && "${SHOW_GROUPS}" != "yes" ]]; then # show when debugging, or when specifically requested
				skip_screen=1
			fi
			level_indicator="🦋"
			inline_logs_color="\e[1;34m" # blue; 36 would be cyan
			skip_logfile=1
			;;

		command)
			if [[ "${SHOW_COMMAND}" != "yes" ]]; then # enable to log all calls to external cmds
				skip_screen=1
			fi
			level_indicator="🐸"
			inline_logs_color="\e[0;36m" # a dim cyan
			;;

		timestamp | fasthash)
			if [[ "${SHOW_FASTHASH}" != "yes" ]]; then # timestamp-related debugging messages, very very verbose
				skip_screen=1
			fi
			level_indicator="🐜"
			inline_logs_color="${tool_color:-}" # either gray or normal, a bit subdued.
			skip_logfile=1
			;;

		extensions)
			if [[ "${SHOW_EXTENSIONS}" != "yes" ]]; then # enable to log a lot about extensions, hook methos, etc.
				skip_screen=1
			fi
			level_indicator="🎣"          # fishing pole and "hook"
			inline_logs_color="\e[0;36m" # a dim cyan
			skip_logfile=1
			;;

		extensionstrace)
			if [[ "${SHOW_EXTENSIONS_TRACE}" != "yes" ]]; then # waaaay too verbose, logs traces in extensions
				skip_screen=1
			fi
			level_indicator="🐾"
			inline_logs_color="\e[0;36m" # a dim cyan
			skip_logfile=1
			;;

		git)
			if [[ "${SHOW_GIT}" != "yes" ]]; then # git-related debugging messages, very very verbose
				skip_screen=1
			fi
			level_indicator="🔖"
			inline_logs_color="${tool_color}" # either gray or normal, a bit subdued.
			skip_logfile=1
			;;

		ccache)
			if [[ "${SHOW_CCACHE}" != "yes" ]]; then # ccache-related debugging messages, very very verbose
				skip_screen=1
			fi
			level_indicator="🙈"
			inline_logs_color="\e[1;34m" # blue; 36 would be cyan
			skip_logfile=1
			;;

		# @TODO this is dead I think
		aggregation)
			if [[ "${SHOW_AGGREGATION}" != "yes" ]]; then # aggregation (PACKAGE LISTS), very very verbose
				skip_screen=1
			fi
			level_indicator="📦"
			inline_logs_color="\e[0;32m"
			skip_logfile=1
			;;

		*)
			level="${level:-info}" # for file logging.
			level_indicator="🌿"
			inline_logs_color="\e[1;37m"
			;;
	esac

	if [[ -n ${2} ]]; then
		extra=" [${inline_logs_color} ${2} ${normal_color:-}]"
		# extra_file=" [${inline_logs_color} ${2} ${normal_color}]" # too much color in logfile
		extra_file=" [ ${2} ]"
	fi

	# Log to journald, if asked to.
	if [[ "${ARMBIAN_LOGS_TO_JOURNAL}" == "yes" ]]; then
		echo -e "${level}: ${1} [ ${2} ]" | sed 's/\x1b\[[0-9;]*m//g' | systemd-cat --identifier="${ARMBIAN_LOGS_JOURNAL_IDENTIFIER:-armbian}"
	fi

	local CALLER_PID="${BASHPID}"

	# Attention: do not pipe the output before writing to the logfile.
	# For example, to remove ansi colors.
	# If you do that, "echo" runs in a subshell due to the "sed" pipe (! important !)
	# for the future: BASHPID is the current subshell; $$ is parent's?; $_ is the current bashopts

	if [[ -f "${CURRENT_LOGFILE}" ]]; then
		# If not asked to skip, or debugging is enabled, log to file.
		if [[ ${skip_logfile} -lt 1 || "${DEBUG}" == "yes" ]]; then
			#echo -e "--> (${SECONDS}) ${level^^}: ${1} [ ${2} ]" >> "${CURRENT_LOGFILE}" # bash ^^ is "to upper case"
			echo -e "--> (${SECONDS}) ${inline_logs_color}${level^^}${normal_color}: ${1}${extra_file}" >> "${CURRENT_LOGFILE}" # bash ^^ is "to upper case"
		fi
	fi

	if [[ ${skip_screen} -eq 1 ]]; then
		return 0
	fi

	local timing_info=""
	if [[ "${SHOW_TIMING}" == "yes" ]]; then
		timing_info="${tool_color}(${normal_color}$(printf "%3s" "${SECONDS}")${tool_color})" # SECONDS is bash builtin for seconds since start of script.
	fi

	local pids_info=""
	if [[ "${SHOW_PIDS}" == "yes" ]]; then
		pids_info="${tool_color}(${normal_color}$$ - ${CALLER_PID}${tool_color})" # BASHPID is the current subshell (should be equal to CALLER_PID here); $$ is parent's?
	fi

	local bashopts_info=""
	if [[ "${SHOW_BASHOPTS}" == "yes" ]]; then
		bashopts_info="${tool_color}(${normal_color}$-${tool_color})" # $- is the currently active bashopts
	fi

	echo -e "${normal_color}${left_marker:-}${padding:-}${level_indicator}${padding}${normal_color}${right_marker:-}${timing_info}${pids_info}${bashopts_info} ${normal_color}${message}${extra}${normal_color}" >&2

	# Now write to CI, if we're running on it. Remove ANSI escapes which confuse GitHub Actions.
	if [[ "${CI}" == "true" ]] && [[ "${ci_log}" != "" ]]; then
		echo -e "::${ci_log} ::" "${1} ${2}" | sed 's/\x1b\[[0-9;]*m//g' >&2
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

## Color	echo -e command
## Black	echo -e "\033[30mBlack\033[0m"
## Bright Black	echo -e "\033[90mBright Black\033[0m"
## Red	echo -e "\033[31mRed\033[0m"
## Bright Red	echo -e "\033[91mBright Red\033[0m"
## Green	echo -e "\033[32mGreen\033[0m"
## Bright Green	echo -e "\033[92mBright Green\033[0m"
## Yellow	echo -e "\033[33mYellow\033[0m"
## Bright Yellow	echo -e "\033[93mBright Yellow\033[0m"
## Blue	echo -e "\033[34mBlue\033[0m"
## Bright Blue	echo -e "\033[94mBright Blue\033[0m"
## Magenta	echo -e "\033[35mMagenta\033[0m"
## Bright Magenta	echo -e "\033[95mBright Magenta\033[0m"
## Cyan	echo -e "\033[36mCyan\033[0m"
## Bright Cyan	echo -e "\033[96mBright Cyan\033[0m"
## White	echo -e "\033[37mWhite\033[0m"
## Bright White	echo -e "\033[97mBright White\033[0m"
