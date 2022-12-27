
function get_file_modification_time() { # @TODO: This is almost always called from a subshell. No use throwing errors?
	local -i file_date
	if [[ ! -f "${1}" ]]; then
		exit_with_error "Can't get modification time of nonexisting file" "${1}"
		return 1
	fi
	# YYYYMMDDhhmm.ss - it is NOT a valid integer, but is what 'touch' wants for its "-t" parameter
	# YYYYMMDDhhmmss - IS a valid integer and we can do math to it. 'touch' code will format it later
	file_date=$(date +%Y%m%d%H%M%S -r "${1}")
	display_alert "Read modification date for file" "${1} - ${file_date}" "timestamp"
	echo -n "${file_date}"
	return 0
}

function get_dir_modification_time() {
	local -i file_date
	if [[ ! -d "${1}" ]]; then
		exit_with_error "Can't get modification time of nonexisting dir" "${1}"
		return 1
	fi
	# YYYYMMDDhhmm.ss - it is NOT a valid integer, but is what 'touch' wants for its "-t" parameter
	# YYYYMMDDhhmmss - IS a valid integer and we can do math to it. 'touch' code will format it later
	file_date=$(date +%Y%m%d%H%M%S -r "${1}")
	display_alert "Read modification date for DIRECTORY" "${1} - ${file_date}" "timestamp"
	echo -n "${file_date}"
	return 0
}

# This is for simple "set without thinking" usage, date preservation is done directly by process_patch_file
function set_files_modification_time() {
	local -i mtime="${1}"
	local formatted_mtime
	shift
	display_alert "Setting date ${mtime}" "${*} (no newer check)" "timestamp"
	formatted_mtime="${mtime:0:12}.${mtime:12}"
	touch --no-create -m -t "${formatted_mtime}" "${@}"
}
