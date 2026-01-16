#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
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
# run_memoized caches the contents of a caller-provided associative array by invoking a named function, storing/loading the array to a disk cache file keyed by inputs and function body, and serializing access with a timed flock and configurable TTL.
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

	declare -i memoize_cache_ttl=${memoize_cache_ttl:-3600} # 1 hour default; can be overriden from outer scope

	# Lock with timeout and user feedback
	exec {lock_fd}> "${disk_cache_file}.lock" || exit_with_error "failed to open lock file"

	# Try non-blocking flock first
	if ! flock -n "${lock_fd}"; then
		# Lock is held by another process, inform user and wait with periodic feedback
		display_alert "Waiting for lock" "another build may be running; check: docker ps -a | grep armbian" "info"

		declare -i lock_wait_interval=${MEMOIZE_FLOCK_WAIT_INTERVAL:-10}  # seconds between retries/messages
		declare -i lock_max_wait=${MEMOIZE_FLOCK_MAX_WAIT:-0}             # 0 = infinite (default for compatibility)
		declare -i lock_total_wait=0
		declare -i lock_acquired=0

		while [[ "${lock_acquired}" -eq 0 ]]; do
			# Try with timeout
			if flock -w "${lock_wait_interval}" "${lock_fd}"; then
				lock_acquired=1
			else
				lock_total_wait=$((lock_total_wait + lock_wait_interval))
				display_alert "Still waiting for lock" "waited ${lock_total_wait}s; Ctrl+C to abort" "warn"

				# Check max wait timeout (0 = infinite)
				if [[ "${lock_max_wait}" -gt 0 && "${lock_total_wait}" -ge "${lock_max_wait}" ]]; then
					display_alert "Lock wait timeout" "exceeded ${lock_max_wait}s; check for stale containers: docker ps -a | grep armbian" "err"
					exit_with_error "flock() timed out after ${lock_total_wait}s - possible stale build process"
				fi
			fi
		done

		display_alert "Lock obtained after waiting" "${lock_total_wait}s" "info"
	else
		display_alert "Lock obtained" "${disk_cache_file}.lock" "debug"
	fi

	if [[ -f "${disk_cache_file}" ]]; then
		declare disk_cache_file_mtime_seconds
		disk_cache_file_mtime_seconds="$(stat -c %Y "${disk_cache_file}")"
		# if disk_cache_file is older than the ttl, delete it and continue.
		if [[ "${disk_cache_file_mtime_seconds}" -lt "$(($(date +%s) - memoize_cache_ttl))" ]]; then
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