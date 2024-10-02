#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function cli_undecided_pre_run() {
	# If undecided, run the 'build' command.
	display_alert "cli_undecided_pre_run" "func cli_undecided_pre_run go to build" "debug"
	ARMBIAN_CHANGE_COMMAND_TO="build"
}

function cli_undecided_run() {
	exit_with_error "Should never run the undecided command. How did this happen?"
}
