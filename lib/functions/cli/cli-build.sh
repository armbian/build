#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function cli_standard_build_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function cli_standard_build_run() {
	declare -g -r BUILDING_IMAGE=yes # Marker; meaning "we are building an image, not just an artifact"
	declare -g -r NEEDS_BINFMT="yes" # Marker; make sure binfmts are installed during prepare_host_interactive

	# configuration etc - it initializes the extension manager; handles its own logging sections
	prep_conf_main_build_single

	# the full build. It has its own logging sections.
	do_with_default_build full_build_packages_rootfs_and_image

}
