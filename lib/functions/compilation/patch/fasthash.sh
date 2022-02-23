function report_fashtash_should_execute() {
	report_fasthash "$@"
	# @TODO: if fasthash only, return 1
	return 0
}

function mark_fasthash_done() {
	display_alert "mark_fasthash_done" "$*" "debug"
	return 0
}

function report_fasthash() {
	local type="${1}"
	local obj="${2}"
	local desc="${3}"
	display_alert "report_fasthash" "${type}: ${desc}" "debug"
	return 0
}

function initialize_fasthash() {
	display_alert "initialize_fasthash" "$*" "debug"
	return 0
	declare -a fast_hash_list=()
}

function fasthash_branch() {
	display_alert "fasthash_branch" "$*" "debug"
	return 0
}

function finish_fasthash() {
	display_alert "finish_fasthash" "$*" "debug"
	return 0
}

function fasthash_debug() {
	display_alert "fasthash_debug" "$*" "debug"
	if [[ "${SHOW_DEBUG}" != "yes" ]]; then # enable debug for many, many debugging msgs
		return 0
	fi
	find . -type f -printf '%T@ %p\n' |
		grep -v -e "\.ko" -e "\.o" -e "\.cmd" -e "\.mod" -e "\.a" -e "\.tmp" -e "\.dtb" -e ".scr" -e "\.\/debian" |
		sort -n | tail -n 10 1>&2
}

function get_file_modification_time() {
	local file_date
	if [[ ! -f "${1}" ]]; then
		exit_with_error "Can't get modification time of nonexisting file" "${1}"
	fi

	# [[CC]YY]MMDDhhmm.[ss] - it is NOT a valid integer
	file_date=$(date +%Y%m%d%H%M.%S -r "${1}")
	display_alert "Got date ${file_date} for file" "${1}" "debug"

	# @TODO: if MIN_PATCH_AGE
	echo -n "${file_date}"

	return 0
}

function set_files_modification_time() {
	local mtime="${1}"
	shift
	display_alert "Setting date ${mtime} " "${*}" "debug"
	touch -m -t "${mtime}" "${@}"
}
