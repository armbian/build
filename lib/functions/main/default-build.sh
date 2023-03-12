#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# This does NOT run under the logging manager.
function full_build_packages_rootfs_and_image() {

	main_default_build_packages # has its own logging sections # requires aggregation

	# build rootfs, if not only kernel. Again, read "KERNEL_ONLY" as if it was "PACKAGES_ONLY"
	if [[ "${KERNEL_ONLY}" != "yes" ]]; then
		display_alert "Building image" "${BOARD}" "target-started"
		assert_requires_aggregation # Bombs if aggregation has not run
		build_rootfs_and_image      # old "debootstrap-ng"; has its own logging sections.
		display_alert "Done building image" "${BOARD}" "target-reached"
	fi
}

function do_with_default_build() {
	main_default_start_build # Has its own logging, prepares workdir, does prepare_host, aggregation, and
	"${@}"
	main_default_end_build
}
