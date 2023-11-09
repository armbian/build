#!/bin/bash
#
# SPDX-License-Identifier: GPL-2.0
#
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

clear

# Determine system language
system_language=$(locale | grep LANG | cut -d= -f2)
#system_language="es"
#system_language="de"

echo $system_language
# More than one command can map to the same handler. In that case, use ARMBIAN_COMMANDS_TO_VARS_DICT for specific vars.
declare -g -A ARMBIAN_COMMANDS_TO_HANDLERS_DICT=(
        ["docker"]="docker" # thus requires cli_docker_pre_run and cli_docker_run
		["docker-purge"]="docker"
		["dockerpurge"]="docker"
		["docker-shell"]="docker"
		["dockershell"]="docker"
		["generate-dockerfile"]="docker"
		["requirements"]="requirements" # implemented in cli_requirements_pre_run and cli_requirements_run
		["configdump"]="config_dump_json"
		["config-dump"]="config_dump_json"
		["config-dump-json"]="config_dump_json"
		["config-dump-no-json"]="config_dump_json"
		["inventory"]="json_info"
		["targets"]="json_info"
		["targets-dashboard"]="json_info"
		["targets-composed"]="json_info"
		["debs-to-repo-json"]="json_info"
		["gha-matrix"]="json_info"
		["gha-workflow"]="json_info"
		["gha-template"]="json_info"
		["debs-to-repo-download"]="json_info" # implemented in cli_json_info_pre_run and cli_json_info_run
		["debs-to-repo-reprepro"]="json_info" # implemented in cli_json_info_pre_run and cli_json_info_run

		["kernel-patches-to-git"]="patch_kernel"  # implemented in cli_patch_kernel_pre_run and cli_patch_kernel_run
		["rewrite-kernel-patches"]="patch_kernel" # implemented in cli_patch_kernel_pre_run and cli_patch_kernel_run

		["build"]="standard_build" # implemented in cli_standard_build_pre_run and cli_standard_build_run
		["distccd"]="distccd"      # implemented in cli_distccd_pre_run and cli_distccd_run
		["flash"]="flash"          # implemented in cli_flash_pre_run and cli_flash_run
)

# EN ARMBIAN_COMMANDS_TO_HANDLERS_DICT Descritions Groups
declare -A COMMAND_DESCRIPTIONS_EN=(
    ["docker"]="Manage Docker containers"
    ["requirements"]="Install system requirements"
    ["config_dump_json"]="Dump configuration to JSON"
    ["json_info"]="Display JSON information"
    ["patch_kernel"]="Apply kernel patches"
    ["standard_build"]="Perform standard build"
    ["distccd"]="Set up distccd"
    ["flash"]="Flash firmware"
    ["requirements"]="Install system requirements"
    ["config_dump_json"]="Dump configuration to JSON"
    ["json_info"]="Display JSON information"
    ["patch_kernel"]="Apply kernel patches"
    ["standard_build"]="Perform standard build"
    ["distccd"]="Set up distccd"
    ["flash"]="Flash firmware"
)


declare -A COMMAND_DESCRIPTIONS_DE=(
    ["docker"]="Docker Container verwalten"
    ["requirements"]="Systemanforderungen installieren"
    # Fügen Sie hier weitere Befehle auf Deutsch hinzu
    ["config_dump_json"]="..."
    ["json_info"]="..."
    ["patch_kernel"]="..."
    ["standard_build"]="..."
    ["distccd"]="..."
    ["flash"]="..."
    ["requirements"]="..."
    ["config_dump_json"]="..."
    ["json_info"]="..."
    ["patch_kernel"]="..."
    ["standard_build"]="..."
    ["distccd"]="..."
    ["flash"]="..."
)

declare -A COMMAND_DESCRIPTIONS_ES=(
    ["docker"]="Gestionar contenedores Docker"
    ["requirements"]="Instalar requisitos del sistema"
    # Agregue más comandos en español aquí
    ["config_dump_json"]=" ..."
    ["json_info"]="..."
    ["patch_kernel"]=" ..."
    ["standard_build"]=" ..."
    ["distccd"]="..."
    ["flash"]="..."
    ["requirements"]="..."
    ["config_dump_json"]="..."
    ["json_info"]="..."
    ["patch_kernel"]="..."
    ["standard_build"]="..."
    ["distccd"]="..."
    ["flash"]="..."
)

# Set default language to English
COMMAND_DESCRIPTIONS=("${COMMAND_DESCRIPTIONS_EN[@]}")

# Choose array based on system language
if [[ $system_language == "de"* ]]; then
    COMMAND_DESCRIPTIONS=("${COMMAND_DESCRIPTIONS_DE[@]}")
elif [[ $system_language == "es"* ]]; then
    COMMAND_DESCRIPTIONS=("${COMMAND_DESCRIPTIONS_ES[@]}")
fi



generate_descriptions() {
    mapfile -t commands < <(printf '%s\n' "${!ARMBIAN_COMMANDS_TO_HANDLERS_DICT[@]}")

    local i=1
    local command
    local description

    for command in "${commands[@]}"; do
        description="${COMMAND_DESCRIPTIONS[${ARMBIAN_COMMANDS_TO_HANDLERS_DICT[$command]}]}"
        handler="${ARMBIAN_COMMANDS_TO_HANDLERS_DICT[$command]}"
        printf '%d %s  - %s\n    ["%s"]="%s"\n' "$i" "$command" "$description" "$command" "$handler"
        ((i++))
    done
}

generate_json() {
    local i=1
    local command
    local description
    mapfile -t commands < <(printf '%s\n' "${!ARMBIAN_COMMANDS_TO_HANDLERS_DICT[@]}")

    # Start JSON array
    json_output="["

    for command in "${commands[@]}"; do
        description="${COMMAND_DESCRIPTIONS[${ARMBIAN_COMMANDS_TO_HANDLERS_DICT[$command]}]}"
        handler="${ARMBIAN_COMMANDS_TO_HANDLERS_DICT[$command]}"

        if [[ $i -gt 1 ]]; then
            json_output+=", "
        fi

        # Append JSON object to the array
        json_output+=$(printf '{"command": "%s", "description": "%s", "handler": "%s"}' "$command" "$description" "$handler")

        ((i++))
    done

    # End JSON array
    json_output+="]"

    # Print the formatted JSON
    echo "$json_output" | jq
}

generate_help_message() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h  Display this help message"
    echo "  -n  Generate Numbered output "
	echo "  -j  Generate a json output "
}

# Call the function
while getopts "hbjJmn" opt; do
    case "$opt" in
	h)  generate_help_message ; exit 0 ;;
	n)  generate_descriptions; exit 0 ;;
	j)  generate_json; exit 0 ;;
    *) echo "Invalid option"; generate_help_message; exit 1 ;;
    esac
done

if [[ $1 == *"--"* ]]; then
    echo "Error: Invalid option detected"
    exit 1
elif [[ -n $1 ]] && ! [[ $1 == --* || $1 == -* ]]; then
    bash ./compile.sh "$@"
elif [[ -z $1 ]]; then
    generate_help_message ; exit 1
fi
