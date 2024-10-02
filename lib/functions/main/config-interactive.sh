#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function config_possibly_interactive_kernel_board() {
	# if KERNEL_CONFIGURE, BOARD, BRANCH or RELEASE are not set, display selection menu

	interactive_config_ask_kernel
	[[ -z $KERNEL_CONFIGURE ]] && exit_with_error "No option selected: KERNEL_CONFIGURE"

	interactive_config_ask_board_list # this uses get_list_of_all_buildable_boards
	[[ -z $BOARD ]] && exit_with_error "No board selected: BOARD"

	return 0 # shortcircuit above
}

function config_possibly_interactive_branch_release_desktop_minimal() {
	interactive_config_ask_branch
	[[ -z $BRANCH ]] && exit_with_error "No kernel branch selected: BRANCH"

	# Check for BRANCH validity, warn but don't break the build if invalid; mark it as invalid for later checks -- if really no valid config, common.conf will exit with error later.
	declare -g BRANCH_VALID_FOR_BOARD='yes'
	if [[ ${KERNEL_TARGET} != *${BRANCH}* && ${BRANCH} != "ddk" ]]; then
		display_alert "BRANCH not found for board" "BRANCH='${BRANCH}' not valid for BOARD='${BOARD}' - listed KERNEL_TARGET='${KERNEL_TARGET}'" "warn"
		declare -g BRANCH_VALID_FOR_BOARD='no'
	fi

	interactive_config_ask_release
	# If building image or rootfs (and thus "NEEDS_BINFMT=yes"), then RELEASE must be set.
	[[ -z $RELEASE && ${NEEDS_BINFMT} == yes ]] && exit_with_error "No release selected: RELEASE"

	interactive_config_ask_desktop_build
	interactive_config_ask_standard_or_minimal

	return 0 # protect against eventual shortcircuit above
}
