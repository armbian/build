#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function armbian_register_commands() {
	# More than one command can map to the same handler. In that case, use ARMBIAN_COMMANDS_TO_VARS_DICT for specific vars.
	declare -g -A ARMBIAN_COMMANDS_TO_HANDLERS_DICT=(
		["docker"]="docker" # thus requires cli_docker_pre_run and cli_docker_run
		["docker-purge"]="docker"
		["dockerpurge"]="docker"
		["docker-shell"]="docker"
		["dockershell"]="docker"
		["generate-dockerfile"]="docker"

		["requirements"]="requirements" # implemented in cli_requirements_pre_run and cli_requirements_run

		# Given a board/config/exts, dump out the (non-userspace) JSON of configuration
		["configdump"]="config_dump_json"       # implemented in cli_config_dump_json_pre_run and cli_config_dump_json_run
		["config-dump-json"]="config_dump_json" # implemented in cli_config_dump_json_pre_run and cli_config_dump_json_run

		["inventory"]="json_info" # implemented in cli_json_info_pre_run and cli_json_info_run
		["targets"]="json_info"   # implemented in cli_json_info_pre_run and cli_json_info_run
		["gha-matrix"]="json_info"    # implemented in cli_json_info_pre_run and cli_json_info_run
		["gha-workflow"]="json_info"  # implemented in cli_json_info_pre_run and cli_json_info_run
		["gha-template"]="json_info"  # implemented in cli_json_info_pre_run and cli_json_info_run

		["kernel-patches-to-git"]="patch_kernel" # implemented in cli_patch_kernel_pre_run and cli_patch_kernel_run

		["build"]="standard_build" # implemented in cli_standard_build_pre_run and cli_standard_build_run
		["distccd"]="distccd"      # implemented in cli_distccd_pre_run and cli_distccd_run
		["flash"]="flash"          # implemented in cli_flash_pre_run and cli_flash_run

		# external tooling, made easy.
		["oras-upload"]="oras" # implemented in cli_oras_pre_run and cli_oras_run; up/down/info are the same, see vars below

		# all-around artifact wrapper
		["artifact"]="artifact"                  # implemented in cli_artifact_pre_run and cli_artifact_run
		["artifact-config-dump-json"]="artifact" # implemented in cli_artifact_pre_run and cli_artifact_run

		# shortcuts, see vars set below. the use legacy single build, and try to control it via variables
		["rootfs"]="artifact"

		["kernel"]="artifact"
		["kernel-patch"]="artifact"
		["kernel-config"]="artifact"

		["uboot"]="artifact"
		["uboot-patch"]="artifact"
		["atf-patch"]="artifact"
		["uboot-config"]="artifact"

		["firmware"]="artifact"
		["firmware-full"]="artifact"
		["armbian-config"]="artifact"
		["armbian-zsh"]="artifact"
		["armbian-plymouth-theme"]="artifact"
		["fake-ubuntu-advantage-tools"]="artifact"

		["armbian-bsp-cli"]="artifact"
		["armbian-bsp-desktop"]="artifact"
		["armbian-desktop"]="artifact"

		["undecided"]="undecided" # implemented in cli_undecided_pre_run and cli_undecided_run - relaunches either build or docker
	)

	# common for all CLI-based artifact shortcuts
	declare common_cli_artifact_vars=""

	# common for interactive artifact shortcuts (configure, patch, etc)
	declare common_cli_artifact_interactive_vars="ARTIFACT_WILL_NOT_BUILD='yes' ARTIFACT_BUILD_INTERACTIVE='yes' ARTIFACT_IGNORE_CACHE='yes'"

	# Vars to be set for each command. Optional.
	declare -g -A ARMBIAN_COMMANDS_TO_VARS_DICT=(
		["docker-purge"]="DOCKER_SUBCMD='purge'"
		["dockerpurge"]="DOCKER_SUBCMD='purge'"
		["docker-shell"]="DOCKER_SUBCMD='shell'"
		["dockershell"]="DOCKER_SUBCMD='shell'"

		["generate-dockerfile"]="DOCKERFILE_GENERATE_ONLY='yes'"

		["artifact-config-dump-json"]='CONFIG_DEFS_ONLY="yes"'

		# artifact shortcuts
		["rootfs"]="WHAT='rootfs' ${common_cli_artifact_vars}"

		["kernel"]="WHAT='kernel' ${common_cli_artifact_vars}"
		["kernel-config"]="WHAT='kernel' KERNEL_CONFIGURE='yes' ${common_cli_artifact_interactive_vars} ${common_cli_artifact_vars}"
		["kernel-patch"]="WHAT='kernel' CREATE_PATCHES='yes' ${common_cli_artifact_interactive_vars} ${common_cli_artifact_vars}"

		["uboot"]="WHAT='uboot' ${common_cli_artifact_vars}"
		["uboot-config"]="WHAT='uboot' UBOOT_CONFIGURE='yes' ${common_cli_artifact_interactive_vars} ${common_cli_artifact_vars}"
		["uboot-patch"]="WHAT='uboot' CREATE_PATCHES='yes' ${common_cli_artifact_interactive_vars} ${common_cli_artifact_vars}"
		["atf-patch"]="WHAT='uboot' CREATE_PATCHES_ATF='yes' ${common_cli_artifact_interactive_vars} ${common_cli_artifact_vars}"

		["firmware"]="WHAT='firmware' ${common_cli_artifact_vars}"
		["firmware-full"]="WHAT='full_firmware' ${common_cli_artifact_vars}"
		["armbian-config"]="WHAT='armbian-config' ${common_cli_artifact_vars}"
		["armbian-zsh"]="WHAT='armbian-zsh' ${common_cli_artifact_vars}"
		["armbian-plymouth-theme"]="WHAT='armbian-plymouth-theme' ${common_cli_artifact_vars}"
		["fake-ubuntu-advantage-tools"]="WHAT='fake_ubuntu_advantage_tools' ${common_cli_artifact_vars}"

		["armbian-bsp-cli"]="WHAT='armbian-bsp-cli' ${common_cli_artifact_vars}"
		["armbian-bsp-desktop"]="WHAT='armbian-bsp-desktop' BUILD_DESKTOP='yes' ${common_cli_artifact_vars}"
		["armbian-desktop"]="WHAT='armbian-desktop' BUILD_DESKTOP='yes' ${common_cli_artifact_vars}"

		["oras-upload"]="ORAS_OPERATION='upload'"

		["undecided"]="UNDECIDED='yes'"
	)
	# Override the LOG_CLI_ID to change the log file name.
	# Will be set to ARMBIAN_COMMAND if not set after all pre-runs done.
	declare -g ARMBIAN_LOG_CLI_ID

	# Keep a running dict of params/variables. Can't repeat stuff here. Dict.
	declare -g -A ARMBIAN_CLI_RELAUNCH_PARAMS=(["ARMBIAN_RELAUNCHED"]="yes")
	declare -g -A ARMBIAN_CLI_RELAUNCH_ENVS=(["ARMBIAN_RELAUNCHED"]="yes")

	# Keep a running array of config files needed for relaunch.
	declare -g -a ARMBIAN_CLI_RELAUNCH_CONFIGS=()
}
