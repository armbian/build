#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function config_possibly_interactive_kernel_board() {
	# if KERNEL_ONLY, KERNEL_CONFIGURE, BOARD, BRANCH or RELEASE are not set, display selection menu

	interactive_config_ask_kernel
	[[ -z $KERNEL_ONLY ]] && exit_with_error "No option selected: KERNEL_ONLY"
	[[ -z $KERNEL_CONFIGURE ]] && exit_with_error "No option selected: KERNEL_CONFIGURE"

	interactive_config_ask_board_list # this uses get_list_of_all_buildable_boards
	[[ -z $BOARD ]] && exit_with_error "No board selected: BOARD"

	return 0 # shortcircuit above
}

function config_possibly_interactive_branch_release_desktop_minimal() {
	interactive_config_ask_branch
	[[ -z $BRANCH ]] && exit_with_error "No kernel branch selected: BRANCH"
	[[ ${KERNEL_TARGET} != *${BRANCH}* && ${BRANCH} != "ddk" ]] && exit_with_error "Kernel branch not defined for this board: '${BRANCH}' for '${BOARD}'"

	interactive_config_ask_release
	[[ -z $RELEASE && ${KERNEL_ONLY} != yes ]] && exit_with_error "No release selected: RELEASE"

	interactive_config_ask_desktop_build
	interactive_config_ask_standard_or_minimal

	return 0 # protect against eventual shortcircuit above
}
