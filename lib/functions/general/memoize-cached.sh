#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# This does many tricks. Beware.
# Also, 'memoize' is a misnomer. It's more like 'cache'.
# It works with bash dictionaries (associative arrays) and references to functions
# It uses bash "declare -f" trick to obtain the function body as a string and use it as part of the caching hash.
# So any changes to the memoized function automatically invalidate the cache.
# It also uses a "cache_id" to allow for multiple caches to be used and to determine the directory name to cache under.
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

	# Lock...
	exec {lock_fd}> "${disk_cache_file}.lock" || exit_with_error "failed to lock"
	flock "${lock_fd}" || exit_with_error "flock() failed"
	display_alert "Lock obtained" "${disk_cache_file}.lock" "debug"

	if [[ -f "${disk_cache_file}" ]]; then
		declare disk_cache_file_mtime_seconds
		disk_cache_file_mtime_seconds="$(stat -c %Y "${disk_cache_file}")"
		# if disk_cache_file is older than 1 hour, delete it and continue.
		if [[ "${disk_cache_file_mtime_seconds}" -lt "$(($(date +%s) - 3600))" ]]; then
			display_alert "Deleting stale cache file" "${disk_cache_file}" "debug"
			rm -f "${disk_cache_file}"
		else
			display_alert "Using memoized ${var_n} from ${disk_cache_file}" "${MEMO_DICT[MEMO_INPUT]}" "debug"
			display_alert "Using cached" "${var_n}" "info"
			# shellcheck disable=SC1090 # yep, I'm sourcing the cache here. produced below.
			source "${disk_cache_file}"
			return 0
		fi
	fi

	# if cache miss, run the memoized_func...
	display_alert "Memoizing ${var_n} to ${disk_cache_file}" "${MEMO_DICT[MEMO_INPUT]}" "debug"
	display_alert "Producing new & caching" "${var_n}" "info"
	${memoized_func} "${var_n}" "${extra_args[@]}"

	# ... and save the output to the cache; twist declare -p's output due to the nameref
	declare -p "${var_n}" | sed -e 's|^declare -A ||' > "${disk_cache_file}"

	# ... unlock.
	flock -u "${lock_fd}"

	return 0
}
