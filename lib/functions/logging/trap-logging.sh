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
	mkdir_recursive_and_set_uid_owner "${target_path}" # @TODO: this might be full of logs and is slow

	# Before writing new logfile, compress and move existing ones to archive folder.
	# - Unless running under CI.
	# - Also not if signalled via SKIP_LOG_ARCHIVE=yes

	if [[ "${CI:-false}" != "true" && "${SKIP_LOG_ARCHIVE:-no}" != "yes" ]]; then
		declare -a existing_log_files_array # array of existing log files: dash and dot in filename required.
		mapfile -t existing_log_files_array < <(find "${target_path}" -maxdepth 1 -type f -name "*-*.*")

		# if more than 7 log files, warn user...
		if [[ "${#existing_log_files_array[@]}" -gt 7 ]]; then
			# Hey, I fixed Docker archiving, so this should not happen again... heh.
			display_alert "Archiving" "${#existing_log_files_array[@]} old log files - be patient & thanks for testing armbian-next! 👍" "wrn"
			wait_for_disk_sync # for dramatic effect
		fi

		declare one_old_logfile old_logfile_fn target_archive_path="${target_path}"/archive
		for one_old_logfile in "${existing_log_files_array[@]}"; do
			old_logfile_fn="$(basename "${one_old_logfile}")"
			if [[ "${old_logfile_fn}" == *${ARMBIAN_BUILD_UUID}* ]]; then
				display_alert "Skipping archiving of current logfile" "${old_logfile_fn}" "cleanup"
				continue
			fi
			display_alert "Archiving old logfile" "${old_logfile_fn}" "cleanup"
			mkdir_recursive_and_set_uid_owner "${target_archive_path}" # @TODO: slow

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

	## Here -- we need to definitely stop logging, cos we're gonna consolidate and delete the logs.
	display_alert "End of logging" "STOP LOGGING: CURRENT_LOGFILE: ${CURRENT_LOGFILE}" "debug"

	# Stop logging to file...
	CURRENT_LOGFILE=""
	unset CURRENT_LOGFILE

	# Check if fd 13 is still open; close it and wait for tee to die. This is done again in discard_logs_tmp_dir()
	check_and_close_fd_13

	# Export ANSI logs.
	local target_file="${target_path}/log-${ARMBIAN_LOG_CLI_ID}-${ARMBIAN_BUILD_UUID}.log.ans"
	export_ansi_logs
	reset_uid_owner "${target_file}"
	local ansi_log_file="${target_file}"

	# ASCII logs, via ansi2txt, if available.
	local ascii_log_file="${target_path}/log-${ARMBIAN_LOG_CLI_ID}-${ARMBIAN_BUILD_UUID}.log"
	if [[ -n "$(command -v ansi2txt)" ]]; then
		# shellcheck disable=SC2002 # gotta pipe, man. I know.
		cat "${ansi_log_file}" | ansi2txt >> "${ascii_log_file}"
	fi

	# Export Markdown assets.
	local target_file="${target_path}/summary-${ARMBIAN_LOG_CLI_ID}-${ARMBIAN_BUILD_UUID}.md"
	export_markdown_logs "${ascii_log_file}" # it might include the ASCII as well, if in GHA.
	reset_uid_owner "${target_file}"
	local markdown_log_file="${target_file}"

	# If running in Github Actions, cat the markdown file to GITHUB_STEP_SUMMARY. It appends, docker and build logs will be together.
	if [[ "${CI}" == "true" ]] && [[ "${GITHUB_ACTIONS}" == "true" ]]; then
		display_alert "Exporting Markdown logs to GitHub Actions" "GITHUB_STEP_SUMMARY: '${GITHUB_STEP_SUMMARY}'" "info"
		cat "${markdown_log_file}" >> "${GITHUB_STEP_SUMMARY}" || true
	fi

	discard_logs_tmp_dir
}
