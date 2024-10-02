# Hint for GitHub Copilot: # Think carefully. Work step by step. # Use modern bash (v5+) features to make it easier to read and maintain.

#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

declare -g -A STORED_CONFIG_VARS=()
function track_config_variables() {
	declare when="${1}"
	shift

	declare -a vars=("${@}")
	declare var_name
	for var_name in "${vars[@]}"; do
		declare var_value var_previous_value was_text value_text

		# if the var is an array...
		if [[ "${array_values:-"no"}" == "yes" ]]; then
			eval "var_value=\"\${${var_name}[@]}\"" # sorry
			value_text="${blue_color:-}(${bright_blue_color:-}${var_value}${blue_color:-})"
		else
			var_value="${!var_name}"
			value_text="${blue_color:-}'${bright_blue_color:-}${var_value}${blue_color:-}'"
		fi

		var_previous_value="${STORED_CONFIG_VARS["${var_name}"]}"
		if [[ "${var_value}" == "${var_previous_value}" ]]; then
			continue
		fi
		was_text=""
		if [[ -n "${var_previous_value}" ]]; then
			was_text="  ${tool_color:-}# (was: '${var_previous_value}')"
		fi
		if [[ "${silent:-"no"}" != "yes" ]]; then
			display_alert "change-tracking: ${when}" "${bright_blue_color:-}${var_name}${normal_color:-}=${value_text}${was_text}" "change-tracking"
		fi
		STORED_CONFIG_VARS["${var_name}"]="${var_value}"
	done
}

function track_general_config_variables() {
	track_config_variables "${1}" BOARDFAMILY KERNELSOURCE KERNEL_MAJOR_MINOR KERNELBRANCH LINUXFAMILY LINUXCONFIG KERNELPATCHDIR KERNEL_PATCH_ARCHIVE_BASE
	array_values="yes" track_config_variables "${1}" KERNEL_DRIVERS_SKIP
	track_config_variables "${1}" BOOTSOURCE BOOTSOURCEDIR BOOTBRANCH BOOTPATCHDIR BOOTDIR BOOTCONFIG BOOTBRANCH_BOARD BOOTPATCHDIR_BOARD
	track_config_variables "${1}" ATFSOURCEDIR ATFDIR ATFBRANCH CRUSTSOURCEDIR CRUSTDIR CRUSTBRANCH LINUXSOURCEDIR
	track_config_variables "${1}" NETWORKING_STACK SKIP_ARMBIAN_REPO
}
