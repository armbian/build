# This does many tricks. Beware.
# Call:
# run_memoized VAR_NAME cache_id memoized_function_name [function_args]
function run_memoized() {
	declare var_n="${1}"
	shift
	declare cache_id="${1}"
	shift
	declare memoized_func="${1}"
	shift
	declare extra_args=("${@}")

	# shellcheck disable=SC2178 # nope, that's a nameref.
	declare -n MEMO_DICT="${var_n}" # nameref

	#display_alert "memoize" "before" "info"
	#debug_dict MEMO_DICT

	MEMO_DICT+=(["MEMO_TYPE"]="${cache_id}")
	declare single_string_input="${cache_id}"
	single_string_input="$(declare -p "${var_n}")" # this might use random order...

	MEMO_DICT+=(["MEMO_INPUT_HASH"]="$(echo "${var_n}-${single_string_input}--$(declare -f "${memoized_func}")" "${extra_args[@]}" | sha256sum | cut -f1 -d' ')")

	declare disk_cache_dir="${SRC}/cache/memoize/${MEMO_DICT[MEMO_TYPE]}"
	mkdir -p "${disk_cache_dir}"
	declare disk_cache_file="${disk_cache_dir}/${MEMO_DICT[MEMO_INPUT_HASH]}"
	if [[ -f "${disk_cache_file}" ]]; then
		# @TODO: check expiration;  some stuff might want different expiration times, eg, branch vs tag vs commit

		display_alert "Using memoized ${var_n} from ${disk_cache_file}" "${MEMO_DICT[MEMO_INPUT]}" "info"
		cat "${disk_cache_file}"
		# shellcheck disable=SC1090 # yep, I'm sourcing the cache here. produced below.
		source "${disk_cache_file}"

		#display_alert "after cache hit" "before" "info"
		#debug_dict MEMO_DICT
		return 0
	fi

	display_alert "Memoizing ${var_n} to ${disk_cache_file}" "${MEMO_DICT[MEMO_INPUT]}" "info"
	# if cache miss, run the memoized_func...
	${memoized_func} "${var_n}" "${extra_args[@]}"

	# ... and save the output to the cache; twist declare -p's output due to the nameref
	declare -p "${var_n}" | sed -e 's|^declare -A ||' > "${disk_cache_file}"

	#display_alert "after cache miss" "before" "info"
	#debug_dict MEMO_DICT

	return 0
}
