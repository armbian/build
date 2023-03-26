#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function cli_config_dump_json_pre_run() {
	declare -g -r CONFIG_DEFS_ONLY='yes' # @TODO: This is actually too late (early optimizations in logging etc), so callers should also set it in the environment when using CLI. sorry.
}

function cli_config_dump_json_run() {
	# configuration etc - it initializes the extension manager
	do_capturing_defs config_board_and_remove_useless < /dev/null # this sets CAPTURED_VARS_NAMES and CAPTURED_VARS_ARRAY; the < /dev/null is take away the terminal from stdin

	# convert to JSON, using python helper; each var is passed via a command line argument; that way we avoid newline/nul-char separation issues
	python3 "${SRC}/lib/tools/configdump2json.py" "--args" "${CAPTURED_VARS_ARRAY[@]}" # to stdout

	return 0
}

function config_board_and_remove_useless() {
	skip_host_config=yes use_board=yes skip_kernel=no do_logging=no prep_conf_main_minimal_ni # avoid logging during configdump; it's useless; skip host config
	unset FINALDEST
	unset DEB_STORAGE
	unset ROOTPWD
}
