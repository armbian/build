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

	# Export Markdown assets.
	local target_file="${target_path}/armbian-${ARMBIAN_LOG_CLI_ID}-${ARMBIAN_BUILD_UUID}.md"
	export_markdown_logs
	reset_uid_owner "${target_file}"

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
