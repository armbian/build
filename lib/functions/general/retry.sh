# Auto retries the number of times passed on first argument to run all the other arguments.
function do_with_retries() {
	local retries="${1}"
	shift

	local sleep_seconds="${sleep_seconds:-5}"
	local silent_retry="${silent_retry:-no}"

	local counter=0
	while [[ $counter -lt $retries ]]; do
		counter=$((counter + 1))
		declare -i RETRY_RUNS=${counter}
		"$@" && return 0 # execute and return 0 if success; if not, let it loop;
		if [[ "${silent_retry}" == "yes" ]]; then
			: # do nothing
		else
			display_alert "Command failed, retrying in ${sleep_seconds}s" "$*" "warn"
		fi
		unset RETRY_RUNS
		sleep "${sleep_seconds}"
	done
	display_alert "Command failed ${counter} times, giving up" "$*" "warn"
	return 1
}
