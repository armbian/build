#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# Parse a single numeric field from "ccache --print-stats" tab-separated output
# Returns 0 if field not found or not numeric
function ccache_get_stat() {
	local stats_output="$1" field="$2"
	local val
	val=$(echo "$stats_output" | grep "^${field}" | cut -f2 || true)
	[[ "${val}" =~ ^[0-9]+$ ]] || val=0
	echo "$val"
}

# Calculate hit percentage from hit and miss counts
function ccache_hit_pct() {
	local hit="$1" miss="$2"
	local total=$(( hit + miss ))
	if [[ $total -gt 0 ]]; then
		echo $(( hit * 100 / total ))
	else
		echo 0
	fi
}

# Helper function to show ccache stats - used as cleanup handler for interruption case
function ccache_show_compilation_stats() {
	local stats_output direct_hit direct_miss pct
	stats_output=$(ccache --print-stats 2>&1 || true)
	direct_hit=$(ccache_get_stat "$stats_output" "direct_cache_hit")
	direct_miss=$(ccache_get_stat "$stats_output" "direct_cache_miss")
	pct=$(ccache_hit_pct "$direct_hit" "$direct_miss")
	display_alert "Ccache result" "hit=${direct_hit} miss=${direct_miss} (${pct}%)" "info"

	# Hook for extensions to show additional stats (e.g., remote storage)
	call_extension_method "ccache_post_compilation" <<- 'CCACHE_POST_COMPILATION'
		*called after ccache-wrapped compilation completes (success or failure)*
		Useful for displaying remote cache statistics or other post-build info.
	CCACHE_POST_COMPILATION
}

function do_with_ccache_statistics() {

	display_alert "Clearing ccache statistics" "ccache" "ccache"
	run_host_command_logged ccache --zero-stats

	if [[ "${SHOW_CCACHE}" == "yes" ]]; then
		# show value of CCACHE_DIR
		display_alert "CCACHE_DIR" "${CCACHE_DIR:-"unset"}" "ccache"
		display_alert "CCACHE_TEMPDIR" "${CCACHE_TEMPDIR:-"unset"}" "ccache"

		# determine what is the actual ccache_dir in use
		local ccache_dir_actual
		ccache_dir_actual="$(ccache --show-config | grep "cache_dir =" | cut -d "=" -f 2 | xargs echo)"

		# calculate the size of that dir, in bytes.
		local ccache_dir_size_before ccache_dir_size_after ccache_dir_size_before_human
		ccache_dir_size_before="$(du -sb "${ccache_dir_actual}" | cut -f 1)"
		ccache_dir_size_before_human="$(numfmt --to=iec-i --suffix=B --format="%.2f" "${ccache_dir_size_before}")"

		# show the human-readable size of that dir, before we start.
		display_alert "ccache dir size before" "${ccache_dir_size_before_human}" "ccache"

		# Show the ccache configuration
		wait_for_disk_sync "before ccache config"
		display_alert "ccache configuration" "ccache" "ccache"
		run_host_command_logged ccache --show-config "&&" sync
	fi

	# Register cleanup handler to show stats even if build is interrupted
	add_cleanup_handler ccache_show_compilation_stats

	display_alert "Running ccache'd build..." "ccache" "ccache"
	local build_exit_code=0
	"$@" || build_exit_code=$?

	# Show stats and remove from cleanup handlers (so it doesn't run twice on exit)
	execute_and_remove_cleanup_handler ccache_show_compilation_stats

	# Re-raise the error if the build failed
	if [[ ${build_exit_code} -ne 0 ]]; then
		return ${build_exit_code}
	fi

	if [[ "${SHOW_CCACHE}" == "yes" ]]; then
		display_alert "Display ccache statistics" "ccache" "ccache"
		run_host_command_logged ccache --show-stats --verbose

		# calculate the size of that dir, in bytes, after the compilation.
		ccache_dir_size_after="$(du -sb "${ccache_dir_actual}" | cut -f 1)"

		# calculate the difference, in bytes.
		local ccache_dir_size_diff
		ccache_dir_size_diff="$((ccache_dir_size_after - ccache_dir_size_before))"

		# calculate the difference, in human-readable format; numfmt is from coreutils.
		local ccache_dir_size_diff_human
		ccache_dir_size_diff_human="$(numfmt --to=iec-i --suffix=B --format="%.2f" "${ccache_dir_size_diff}")"

		# display the difference
		display_alert "ccache dir size change" "${ccache_dir_size_diff_human}" "ccache"
	fi

	return 0
}
