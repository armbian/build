function report_fashtash_should_execute() {
	report_fasthash "$@"
	# @TODO: if fasthash only, return 1
	return 0
}

function mark_fasthash_done() {
	display_alert "mark_fasthash_done" "$*" "fasthash"
	return 0
}

function report_fasthash() {
	local type="${1}"
	local obj="${2}"
	local desc="${3}"
	display_alert "report_fasthash" "${type}: ${desc}" "fasthash"
	return 0
}

function initialize_fasthash() {
	display_alert "initialize_fasthash" "$*" "fasthash"
	return 0
	declare -a fast_hash_list=() # @TODO: declaring here won't do it any good, this is a shared var
}

function fasthash_branch() {
	display_alert "fasthash_branch" "$*" "fasthash"
	return 0
}

function finish_fasthash() {
	display_alert "finish_fasthash" "$*" "fasthash"
	return 0
}

function fasthash_debug() {
	if [[ "${SHOW_FASTHASH}" != "yes" ]]; then
		return 0
	fi
	display_alert "fasthash_debug" "$*" "fasthash"
	run_host_command_logged find . -type f -printf "'%T@ %p\\n'" "|" \
		grep -v -e "\.ko" -e "\.o" -e "\.cmd" -e "\.mod" -e "\.a" -e "\.tmp" -e "\.dtb" -e ".scr" -e "\.\/debian" "|" \
		sort -n "|" tail -n 10
}

function get_file_modification_time() { # @TODO: This is almost always called from a subshell. No use throwing errors?
	local -i file_date
	if [[ ! -f "${1}" ]]; then
		exit_with_error "Can't get modification time of nonexisting file" "${1}"
		return 1
	fi
	# YYYYMMDDhhmm.ss - it is NOT a valid integer, but is what 'touch' wants for its "-t" parameter
	# YYYYMMDDhhmmss - IS a valid integer and we can do math to it. 'touch' code will format it later
	file_date=$(date +%Y%m%d%H%M%S -r "${1}")
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
