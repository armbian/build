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
	if [[ "${ARMBIAN_RUNNING_IN_CONTAINER}" == "yes" ]]; then # if in container, add a cyan "whale emoji" to the left marker wrapped in dark gray brackets
		local container_emoji="🐳"                                #  🐳 or 🐋
		export left_marker="${gray_color}[${container_emoji}|${normal_color}"
	elif [[ "$(uname -s)" == "Darwin" ]]; then # if on Mac, add a an apple emoji to the left marker wrapped in dark gray brackets
		local mac_emoji="🍏"                       # 🍏 or 🍎
		export left_marker="${gray_color}[${mac_emoji}|${normal_color}"
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
			cat "${logfile_to_show}" | grep -v -e "^$" | /usr/bin/ccze -o nolookups -A | sed -e "${prefix_sed_cmd}" 1>&2 # write it to stderr!!
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
	export CURRENT_LOGGING_SECTION_START=${SECONDS}
	export CURRENT_LOGGING_DIR="${LOGDIR}" # set in cli-entrypoint.sh
	export CURRENT_LOGFILE="${CURRENT_LOGGING_DIR}/${CURRENT_LOGGING_COUNTER}.000.${CURRENT_LOGGING_SECTION}.log"
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
		prefix_sed_contents="$(logging_echo_prefix_for_pv "tool")   $(echo -n -e "${tool_color}")" # spaces are significant
		local prefix_sed_cmd="s/^/${prefix_sed_contents}/;"

		# This is sick. Create a 3rd file descriptor sending it to sed. https://unix.stackexchange.com/questions/174849/redirecting-stdout-to-terminal-and-file-without-using-a-pipe
		# Also terrible: don't hold a reference to cwd by changing to SRC always
		exec 3> >(
			cd "${SRC}" || exit 2
			# First, log to file, then add prefix via sed for what goes to screen.
			tee -a "${CURRENT_LOGFILE}" | sed -u -e "${prefix_sed_cmd}"
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

# This takes LOG_ASSET, which can and should include an extension.
function do_with_log_asset() {
	# @TODO: check that CURRENT_LOGGING_COUNTER is set, otherwise crazy?
	local ASSET_LOGFILE="${CURRENT_LOGGING_DIR}/${CURRENT_LOGGING_COUNTER}.${LOG_ASSET}"
	display_alert "Logging to asset" "${CURRENT_LOGGING_COUNTER}.${LOG_ASSET}" "debug"
	"$@" >> "${ASSET_LOGFILE}"
}

function display_alert() {
	# If asked, avoid any fancy ANSI escapes completely. For python-driven log collection. Formatting could be improved.
	# If used, also does not write to logfile even if it exists.
	if [[ "${ANSI_COLOR}" == "none" ]]; then
		echo -e "${@}" | sed 's/\x1b\[[0-9;]*m//g' >&2
		return 0
	fi

	local message="${1}" level="${3}"                                # params
	local level_indicator="" inline_logs_color="" extra="" ci_log="" # this log
	local skip_screen=0                                              # setting to 1 will write to logfile only
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
			;;

		debug | deprecation)
			if [[ "${SHOW_DEBUG}" != "yes" ]]; then # enable debug for many, many debugging msgs
				skip_screen=1
			fi
			level_indicator="🐛"
			inline_logs_color="\e[1;33m"
			;;

		group)
			if [[ "${SHOW_DEBUG}" != "yes" && "${SHOW_GROUPS}" != "yes" ]]; then # show when debugging, or when specifically requested
				skip_screen=1
			fi
			level_indicator="🦋"
			inline_logs_color="\e[1;34m" # blue; 36 would be cyan
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
			inline_logs_color="${tool_color}" # either gray or normal, a bit subdued.
			;;

		extensions)
			if [[ "${SHOW_EXTENSIONS}" != "yes" ]]; then # enable to log a lot about extensions, hook methos, etc.
				skip_screen=1
			fi
			level_indicator="🎣"          # fishing pole and "hook"
			inline_logs_color="\e[0;36m" # a dim cyan
			;;

		extensionstrace)
			if [[ "${SHOW_EXTENSIONS_TRACE}" != "yes" ]]; then # waaaay too verbose, logs traces in extensions
				skip_screen=1
			fi
			level_indicator="🐾"
			inline_logs_color="\e[0;36m" # a dim cyan
			;;

		git)
			if [[ "${SHOW_GIT}" != "yes" ]]; then # git-related debugging messages, very very verbose
				skip_screen=1
			fi
			level_indicator="🔖"
			inline_logs_color="${tool_color}" # either gray or normal, a bit subdued.
			;;

		ccache)
			if [[ "${SHOW_CCACHE}" != "yes" ]]; then # ccache-related debugging messages, very very verbose
				skip_screen=1
			fi
			level_indicator="🙈"
			inline_logs_color="\e[1;34m" # blue; 36 would be cyan
			;;

		aggregation)
			if [[ "${SHOW_AGGREGATION}" != "yes" ]]; then # aggregation (PACKAGE LISTS), very very verbose
				skip_screen=1
			fi
			level_indicator="📦"
			inline_logs_color="\e[0;32m"
			;;

		*)
			level="${level:-other}" # for file logging.
			level_indicator="🌿"
			inline_logs_color="\e[1;37m"
			;;
	esac

	# Log to journald, if asked to.
	if [[ "${ARMBIAN_LOGS_TO_JOURNAL}" == "yes" ]]; then
		echo -e "${level}: ${1} [ ${2} ]" | sed 's/\x1b\[[0-9;]*m//g' | systemd-cat --identifier="${ARMBIAN_LOGS_JOURNAL_IDENTIFIER:-armbian}"
	fi

	# Now, log to file. This will be colorized later by ccze and such, so remove any colors it might already have.
	# See also the stuff done in runners.sh for logging exact command lines and runtimes.
	# the "echo" runs in a subshell due to the "sed" pipe (! important !), so we store BASHPID (current subshell) outside the scope
	# BASHPID is the current subshell; $$ is parent's?; $_ is the current bashopts
	local CALLER_PID="${BASHPID}"
	if [[ -f "${CURRENT_LOGFILE}" ]]; then
		# ANSI-less version
		#echo -e "--> ${level_indicator} $(printf "%4s" "${SECONDS}"): $$ - ${CALLER_PID} - ${BASHPID}: $-: ${level}: ${1} [ ${2} ]" >> "${CURRENT_LOGFILE}" #  | sed 's/\x1b\[[0-9;]*m//g'
		echo -e "--> ${level_indicator} $(printf "%4s" "${SECONDS}"): $$ - ${CALLER_PID} - ${BASHPID}: $-: ${level}: ${1} [ ${2} ]" >> "${CURRENT_LOGFILE}" #  | sed 's/\x1b\[[0-9;]*m//g'
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

	[[ -n $2 ]] && extra=" [${inline_logs_color} ${2} ${normal_color}]"
	echo -e "${normal_color}${left_marker}${padding}${level_indicator}${padding}${normal_color}${right_marker}${timing_info}${pids_info}${bashopts_info} ${normal_color}${message}${extra}${normal_color}" >&2

	# Now write to CI, if we're running on it. Remove ANSI escapes which confuse GitHub Actions.
	if [[ "${CI}" == "true" ]] && [[ "${ci_log}" != "" ]]; then
		echo -e "::${ci_log} ::" "$@" | sed 's/\x1b\[[0-9;]*m//g' >&2
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

# Export logs in plain format.
function export_ansi_logs() {
	display_alert "Preparing ANSI log from" "${LOGDIR}" "debug"

	cat <<- ANSI_HEADER > "${target_file}"
		# Armbian logs for ${ARMBIAN_BUILD_UUID}
		# Armbian build at $(LC_ALL=C LANG=C date) on $(hostname || true)
		----------------------------------------------------------------------------------------------------------------
		# ARGs: ${ARMBIAN_ORIGINAL_ARGV[@]@Q}
		----------------------------------------------------------------------------------------------------------------
	ANSI_HEADER

	if [[ -n "$(command -v git)" && -d "${SRC}/.git" ]]; then
		display_alert "Gathering git info for logs" "Processing git information, please wait..." "debug"
		cat <<- GIT_ANSI_HEADER > "${target_file}"
			----------------------------------------------------------------------------------------------------------------
			# Last revision:
			$(LC_ALL=C LANG=C git --git-dir="${SRC}/.git" log -1 --color --format=short --decorate)
			----------------------------------------------------------------------------------------------------------------
			# Git status:
			$(LC_ALL=C LANG=C git -c color.status=always --work-tree="${SRC}" --git-dir="${SRC}/.git" status)
			----------------------------------------------------------------------------------------------------------------
			# Git changes:
			$(LC_ALL=C LANG=C git --work-tree="${SRC}" --git-dir="${SRC}/.git" diff -u --color)
			----------------------------------------------------------------------------------------------------------------
		GIT_ANSI_HEADER
	fi

	display_alert "Preparing ANSI logs..." "Processing log files..." "debug"

	# Find and sort the files there, store in array one per logfile
	declare -a logfiles_array
	mapfile -t logfiles_array < <(find "${LOGDIR}" -type f | LC_ALL=C sort -h)

	for logfile_full in "${logfiles_array[@]}"; do
		local logfile_base="$(basename "${logfile_full}")"
		cat <<- ANSI_ONE_LOGFILE_NO_CCZE >> "${target_file}"
			------------------------------------------------------------------------------------------------------------
			## ${logfile_base}
			$(cat "${logfile_full}")
			------------------------------------------------------------------------------------------------------------
		ANSI_ONE_LOGFILE_NO_CCZE
	done

	display_alert "Built ANSI log file" "${target_file}"
}

# Export logs in HTML format. (EXPORT_HTML_LOG=yes) -- very slow.
function export_html_logs() {
	display_alert "Preparing HTML log from" "${LOGDIR}" "debug"

	cat <<- ANSI_HEADER > "${target_file}"
		<html>
			<head>
			<title>Armbian logs for ${ARMBIAN_BUILD_UUID}</title>
			<style>
				html, html pre { background-color: black !important; color: white !important; font-family: JetBrains Mono, monospace, cursive !important; }
				hr { border: 0; border-bottom: 1px dashed silver; }
			</style>
			</head>
		<body>
			<h2>Armbian build at $(LC_ALL=C LANG=C date) on $(hostname || true)</h2>
			<h2>${ARMBIAN_ORIGINAL_ARGV[@]@Q}</h2>
			<hr/>

			$(LC_ALL=C LANG=C git --git-dir="${SRC}/.git" log -1 --color --format=short --decorate | ansi2html --no-wrap --no-header)
			<hr/>

			$(LC_ALL=C LANG=C git -c color.status=always --work-tree="${SRC}" --git-dir="${SRC}/.git" status | ansi2html --no-wrap --no-header)
			<hr/>

			$(LC_ALL=C LANG=C git --work-tree="${SRC}" --git-dir="${SRC}/.git" diff -u --color | ansi2html --no-wrap --no-header)
			<hr/>

	ANSI_HEADER

	# Find and sort the files there, store in array one per logfile
	declare -a logfiles_array
	mapfile -t logfiles_array < <(find "${LOGDIR}" -type f | LC_ALL=C sort -h)

	for logfile_full in "${logfiles_array[@]}"; do
		local logfile_base="$(basename "${logfile_full}")"
		if [[ -f /usr/bin/ccze ]] && [[ -f /usr/bin/ansi2html ]]; then
			cat <<- HTML_ONE_LOGFILE_WITH_CCZE >> "${target_file}"
				<h3>${logfile_base}</h3>
				<div style="padding: 1em">
				$(ccze -o nolookups --raw-ansi < "${logfile_full}" | ansi2html --no-wrap --no-header)
				</div>
				<hr/>
			HTML_ONE_LOGFILE_WITH_CCZE
		else
			cat <<- ANSI_ONE_LOGFILE_NO_CCZE >> "${target_file}"
				<h3>${logfile_base}</h3>
				<pre>$(cat "${logfile_full}")</pre>
			ANSI_ONE_LOGFILE_NO_CCZE
		fi
	done

	cat <<- HTML_FOOTER >> "${target_file}"
		</body></html>
	HTML_FOOTER

	display_alert "Built HTML log file" "${target_file}"
}

function discard_logs_tmp_dir() {
	# Linux allows us to be more careful, but really, those are log files we're talking about.
	if [[ "$(uname)" == "Linux" ]]; then
		rm -rf --one-file-system "${LOGDIR}"
	else
		rm -rf "${LOGDIR}"
	fi
}

# Cleanup for logging.
function trap_handler_cleanup_logging() {
	[[ "x${LOGDIR}x" == "xx" ]] && return 0
	[[ "x${LOGDIR}x" == "x/x" ]] && return 0
	[[ ! -d "${LOGDIR}" ]] && return 0

	display_alert "Cleaning up log files" "LOGDIR: '${LOGDIR}'" "debug"

	# `pwd` might not even be valid anymore. Move back to ${SRC}
	cd "${SRC}" || exit_with_error "cray-cray about SRC: ${SRC}"

	# Just delete LOGDIR if in CONFIG_DEFS_ONLY mode.
	if [[ "${CONFIG_DEFS_ONLY}" == "yes" ]]; then
		display_alert "Discarding logs" "CONFIG_DEFS_ONLY=${CONFIG_DEFS_ONLY}" "debug"
		discard_logs_tmp_dir
		return 0
	fi

	local target_path="${DEST}/logs"
	mkdir_recursive_and_set_uid_owner "${target_path}"

	# Before writing new logfile, compress and move existing ones to archive folder.
	# - Unless running under CI.
	# - Also not if signalled via SKIP_LOG_ARCHIVE=yes
	if [[ "${CI:-false}" != "true" && "${SKIP_LOG_ARCHIVE:-no}" != "yes" ]]; then
		declare -a existing_log_files_array
		mapfile -t existing_log_files_array < <(find "${target_path}" -maxdepth 1 -type f -name "armbian-*.*")
		declare one_old_logfile old_logfile_fn target_archive_path="${target_path}"/archive
		for one_old_logfile in "${existing_log_files_array[@]}"; do
			old_logfile_fn="$(basename "${one_old_logfile}")"
			if [[ "${old_logfile_fn}" == *${ARMBIAN_BUILD_UUID}* ]]; then
				display_alert "Skipping archiving of current logfile" "${old_logfile_fn}" "warn"
				continue
			fi
			display_alert "Archiving old logfile" "${old_logfile_fn}" "warn"
			mkdir_recursive_and_set_uid_owner "${target_archive_path}"

			# Check if we have `zstdmt` at this stage; if not, use standard gzip
			if [[ -n "$(command -v zstdmt)" ]]; then
				zstdmt --quiet "${one_old_logfile}" -o "${target_archive_path}/${old_logfile_fn}.zst"
				reset_uid_owner "${target_archive_path}/${old_logfile_fn}.zst"
			else
				# shellcheck disable=SC2002 # my cat is not useless. a bit whiny. not useless.
				cat "${one_old_logfile}" | gzip > "${target_archive_path}/${old_logfile_fn}.gz"
				reset_uid_owner "${target_archive_path}/${old_logfile_fn}.gz"
			fi
			rm -f "${one_old_logfile}"
		done
	else
		display_alert "Not archiving old logs." "CI=${CI:-false}, SKIP_LOG_ARCHIVE=${SKIP_LOG_ARCHIVE:-no}" "debug"
	fi

	if [[ "${EXPORT_HTML_LOG}" == "yes" ]]; then
		local target_file="${target_path}/armbian-${ARMBIAN_LOG_CLI_ID}-${ARMBIAN_BUILD_UUID}.html"
		export_html_logs
		reset_uid_owner "${target_file}"
	fi

	local target_file="${target_path}/armbian-${ARMBIAN_LOG_CLI_ID}-${ARMBIAN_BUILD_UUID}.ansitxt.log"
	export_ansi_logs
	reset_uid_owner "${target_file}"

	discard_logs_tmp_dir
}
