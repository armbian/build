#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

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

	display_alert "Running ccache'd build..." "ccache" "ccache"
	"$@"

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
