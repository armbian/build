#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function cli_config_dump_pre_run() {
	declare -g CONFIG_DEFS_ONLY='yes'
}

function cli_config_dump_run() {
	# configuration etc - it initializes the extension manager
	do_capturing_defs config_and_remove_useless < /dev/null # this sets CAPTURED_VARS; the < /dev/null is take away the terminal from stdin
	echo "${CAPTURED_VARS}"                                 # to stdout!
}

function config_and_remove_useless() {
	do_logging=no prep_conf_main_build_single # avoid logging during configdump; it's useless
	unset FINALDEST
	unset HOOK_ORDER HOOK_POINT HOOK_POINT_TOTAL_FUNCS
	unset REPO_CONFIG REPO_STORAGE
	unset DEB_STORAGE
	unset RKBIN_DIR
	unset ROOTPWD
}
