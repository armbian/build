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

	if [[ "${ARMBIAN_COMMAND}" == "config-dump-no-json" ]]; then
		# for debugging the bash-declare-to-JSON parser
		echo "${CAPTURED_VARS_ARRAY[@]}"
		return 0
	fi

	# convert to JSON, using python helper; each var is passed via a command line argument; that way we avoid newline/nul-char separation issues
	display_alert "Dumping JSON" "for ${#CAPTURED_VARS_ARRAY[@]} variables" "ext"
	python3 "${SRC}/lib/tools/configdump2json.py" "--args" "${CAPTURED_VARS_ARRAY[@]}" # to stdout

	return 0
}

function config_board_and_remove_useless() {
	skip_host_config=yes use_board=yes skip_kernel=no do_logging=no prep_conf_main_minimal_ni # avoid logging during configdump; it's useless; skip host config
	determine_artifacts_needed_and_its_inputs_for_configdump

	# Remove unwanted variables from the config dump JSON.
	unset FINALDEST
	unset DEB_STORAGE
	unset ROOTPWD
}

function determine_artifacts_needed_and_its_inputs_for_configdump() {
	# Determine which artifacts to build.
	declare -a artifacts_to_build=()
	determine_artifacts_to_build_for_image
	display_alert "Artifacts to build:" "${artifacts_to_build[*]}" "info"

	# For each artifact, get the input variables from each.
	declare -a all_wanted_artifact_names=() all_wanted_artifact_vars=()
	declare one_artifact one_artifact_package
	for one_artifact in "${artifacts_to_build[@]}"; do
		declare -g artifact_input_vars

		WHAT="${one_artifact}" dump_artifact_config

		declare WHAT_UPPERCASE="${one_artifact^^}"
		declare WHAT_UPPERCASE_REPLACED="${WHAT_UPPERCASE//[-.]/_}"

		all_wanted_artifact_names+=("${one_artifact}")
		all_wanted_artifact_vars+=("${WHAT_UPPERCASE_REPLACED}")

		eval "declare -r -g WANT_ARTIFACT_${WHAT_UPPERCASE_REPLACED}_INPUTS_ARRAY=\"${artifact_input_vars}\""
	done

	declare -r -g WANT_ARTIFACT_ALL_NAMES_ARRAY="${all_wanted_artifact_names[*]}"
	declare -r -g WANT_ARTIFACT_ALL_ARRAY="${all_wanted_artifact_vars[*]}"
}
