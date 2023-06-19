#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

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
		declare -i IS_A_RETRY=0
		declare RETRY_FMT_MORE_THAN_ONCE=""
		if [[ ${RETRY_RUNS} -gt 1 ]]; then
			IS_A_RETRY=1
			RETRY_FMT_MORE_THAN_ONCE=" (attempt ${RETRY_RUNS})"
		fi

		"$@" && return 0 # execute and return 0 if success; if not, let it loop;
		if [[ "${silent_retry}" == "yes" ]]; then
			: # do nothing
		else
			# skip_ci_special="yes": don't write this warning to CI/GHA summary. retries are normal in GHA and pollute the Summary view
			skip_ci_special="yes" display_alert "Command failed, retrying in ${sleep_seconds}s" "$*" "warn"
		fi
		unset IS_A_RETRY
		unset RETRY_RUNS
		unset RETRY_FMT_MORE_THAN_ONCE
		sleep "${sleep_seconds}"
	done
	display_alert "Command failed ${counter} times, giving up" "$*" "warn"
	return 1
}
