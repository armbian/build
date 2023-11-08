#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/


# More than one command can map to the same handler. In that case, use ARMBIAN_COMMANDS_TO_VARS_DICT for specific vars.
declare -g -A ARMBIAN_COMMANDS_TO_HANDLERS_DICT+=(
		["docker"]="docker" # thus requires cli_docker_pre_run and cli_docker_run
		["docker-purge"]="docker"
		["dockerpurge"]="docker"
		["docker-shell"]="docker"
		["dockershell"]="docker"
		["generate-dockerfile"]="docker"
)

# implemented in cli_requirements_pre_run and cli_requirements_run
ARMBIAN_COMMANDS_TO_HANDLERS_DICT+=(
		["requirements"]="requirements" # implemented in cli_requirements_pre_run and cli_requirements_run
)

# Given a board/config/exts, dump out the (non-userspace) JSON of configuration
ARMBIAN_COMMANDS_TO_HANDLERS_DICT+=(
		["configdump"]="config_dump_json"
		["config-dump"]="config_dump_json"
		["config-dump-json"]="config_dump_json"
		["config-dump-no-json"]="config_dump_json"

		["inventory"]="json_info"         # implemented in cli_json_info_pre_run and cli_json_info_run
		["targets"]="json_info"           # implemented in cli_json_info_pre_run and cli_json_info_run
		["targets-dashboard"]="json_info" # implemented in cli_json_info_pre_run and cli_json_info_run
		["targets-composed"]="json_info"  # implemented in cli_json_info_pre_run and cli_json_info_run
		["debs-to-repo-json"]="json_info" # implemented in cli_json_info_pre_run and cli_json_info_run
		["gha-matrix"]="json_info"        # implemented in cli_json_info_pre_run and cli_json_info_run
		["gha-workflow"]="json_info"      # implemented in cli_json_info_pre_run and cli_json_info_run
		["gha-template"]="json_info"      # implemented in cli_json_info_pre_run and cli_json_info_run
)

# These probably should be in their own separate CLI commands file, but for now they're together in jsoninfo.
ARMBIAN_COMMANDS_TO_HANDLERS_DICT+=(

		["debs-to-repo-download"]="json_info" # implemented in cli_json_info_pre_run and cli_json_info_run
		["debs-to-repo-reprepro"]="json_info" # implemented in cli_json_info_pre_run and cli_json_info_run

		["kernel-patches-to-git"]="patch_kernel"  # implemented in cli_patch_kernel_pre_run and cli_patch_kernel_run
		["rewrite-kernel-patches"]="patch_kernel" # implemented in cli_patch_kernel_pre_run and cli_patch_kernel_run

		["build"]="standard_build" # implemented in cli_standard_build_pre_run and cli_standard_build_run
		["distccd"]="distccd"      # implemented in cli_distccd_pre_run and cli_distccd_run
		["flash"]="flash"          # implemented in cli_flash_pre_run and cli_flash_run
)

#ARMBIAN_COMMANDS_TO_HANDLERS_DICT+=(
#
#)


# Iterate over the keys in the array
see_docker(){
local message
for key in "${!ARMBIAN_COMMANDS_TO_HANDLERS_DICT[@]}"; do
    # Check if the value of the current key is "docker"
    if [ "${ARMBIAN_COMMANDS_TO_HANDLERS_DICT[$key]}" = "docker" ]; then
        # If it is, print the key
        echo "$key"
        message="${ARMBIAN_COMMANDS_TO_HANDLERS_DICT[$key]}"
    fi

done | configng-interface -m
echo "${ARMBIAN_COMMANDS_TO_HANDLERS_DICT["#?"]}"
}



help_message() {
    local i=-1
    for key in "${!ARMBIAN_COMMANDS_TO_HANDLERS_DICT[@]}"; do
    ((++i))
        menu_options+=(" $i " " $key - ${ARMBIAN_COMMANDS_TO_HANDLERS_DICT[$key]} ")
        menu_output+=("${ARMBIAN_COMMANDS_TO_HANDLERS_DICT[$key]}")
    done
    local choice=$(printf '%s %s\n' "${menu_options[@]}" | configng-interface -m)
	echo -e "$choice handled by ${ARMBIAN_COMMANDS_TO_HANDLERS_DICT[$$choice]}\n\t ${menu_output[$choice]}" 
}


help_message | configng-interface -o

