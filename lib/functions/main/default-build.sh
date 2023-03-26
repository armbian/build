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
	error_if_kernel_only_set

	# Detour, warn the user about KERNEL_CONFIGURE=yes if it is set.
	if [[ "${KERNEL_CONFIGURE}" == "yes" ]]; then
		display_alert "KERNEL_CONFIGURE=yes during image build is deprecated." "It still works, but please prefer the new way. First, run './compile.sh BOARD=${BOARD} BRANCH=${BRANCH} kernel-config'; then commit your changes; then build the image as normal. This workflow ensures consistent hashing results." "wrn"
	fi

	main_default_build_packages # has its own logging sections # requires aggregation

	# build rootfs and image
	display_alert "Building image" "${BOARD}" "target-started"
	assert_requires_aggregation # Bombs if aggregation has not run
	build_rootfs_and_image      # old "debootstrap-ng"; has its own logging sections.
	display_alert "Done building image" "${BOARD}" "target-reached"
}

function do_with_default_build() {
	main_default_start_build # Has its own logging, prepares workdir, does prepare_host, aggregation, and
	"${@}"
	main_default_end_build
}
