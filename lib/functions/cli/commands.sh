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
	# The handlers' functions "cli_${ARMBIAN_COMMAND_HANDLER}_pre_run" and "cli_${ARMBIAN_COMMAND_HANDLER}_run" get automatically called in "utils-cli.sh"
	# Example: For command "docker-purge", the handler is "docker", which means the functions "cli_docker_pre_run" and "cli_docker_run" inside "cli-docker.sh are automatically called by "utils-cli.sh"
	declare -g -A ARMBIAN_COMMANDS_TO_HANDLERS_DICT=(
		["docker"]="docker" # thus requires cli_docker_pre_run and cli_docker_run
		["docker-purge"]="docker"
		["dockerpurge"]="docker"
		["docker-shell"]="docker"
		["dockershell"]="docker"
		["generate-dockerfile"]="docker"

		["requirements"]="requirements" # implemented in cli_requirements_pre_run and cli_requirements_run

		# Given a board/config/exts, dump out the (non-userspace) JSON of configuration
		["configdump"]="config_dump_json"          # implemented in cli_config_dump_json_pre_run and cli_config_dump_json_run
		["config-dump"]="config_dump_json"         # implemented in cli_config_dump_json_pre_run and cli_config_dump_json_run
		["config-dump-json"]="config_dump_json"    # implemented in cli_config_dump_json_pre_run and cli_config_dump_json_run
		["config-dump-no-json"]="config_dump_json" # implemented in cli_config_dump_json_pre_run and cli_config_dump_json_run

		["inventory"]="json_info"         # implemented in cli_json_info_pre_run and cli_json_info_run
		["targets"]="json_info"           # implemented in cli_json_info_pre_run and cli_json_info_run
		["targets-dashboard"]="json_info" # implemented in cli_json_info_pre_run and cli_json_info_run
		["inventory-boards"]="json_info"  # implemented in cli_json_info_pre_run and cli_json_info_run
		["targets-composed"]="json_info"  # implemented in cli_json_info_pre_run and cli_json_info_run
		["debs-to-repo-json"]="json_info" # implemented in cli_json_info_pre_run and cli_json_info_run
		["gha-matrix"]="json_info"        # implemented in cli_json_info_pre_run and cli_json_info_run
		["gha-workflow"]="json_info"      # implemented in cli_json_info_pre_run and cli_json_info_run
		["gha-template"]="json_info"      # implemented in cli_json_info_pre_run and cli_json_info_run

		# These probably should be in their own separate CLI commands file, but for now they're together in jsoninfo.
		["debs-to-repo-download"]="json_info" # implemented in cli_json_info_pre_run and cli_json_info_run
		["debs-to-repo-reprepro"]="json_info" # implemented in cli_json_info_pre_run and cli_json_info_run

		# Patch to git & patch rewrite, for kernel
		["kernel-patches-to-git"]="patch_kernel"                 # implemented in cli_patch_kernel_pre_run and cli_patch_kernel_run
		["rewrite-kernel-patches"]="patch_kernel"                # implemented in cli_patch_kernel_pre_run and cli_patch_kernel_run
		["rewrite-kernel-patches-needing-rebase"]="patch_kernel" # implemented in cli_patch_kernel_pre_run and cli_patch_kernel_run

		# Patch to git & patch rewrite, for u-boot
		["uboot-patches-to-git"]="patch_uboot"                 # implemented in cli_patch_uboot_pre_run and cli_patch_uboot_run
		["rewrite-uboot-patches"]="patch_uboot"                # implemented in cli_patch_uboot_pre_run and cli_patch_uboot_run
		["rewrite-uboot-patches-needing-rebase"]="patch_uboot" # implemented in cli_patch_uboot_pre_run and cli_patch_uboot_run

		["build"]="standard_build" # implemented in cli_standard_build_pre_run and cli_standard_build_run
		["distccd"]="distccd"      # implemented in cli_distccd_pre_run and cli_distccd_run
		["flash"]="flash"          # implemented in cli_flash_pre_run and cli_flash_run

		# external tooling, made easy.
		["oras-upload"]="oras" # implemented in cli_oras_pre_run and cli_oras_run; up/down/info are the same, see vars below

		# all-around artifact wrapper
		["artifact"]="artifact"                  # implemented in cli_artifact_pre_run and cli_artifact_run
		["artifact-config-dump-json"]="artifact" # implemented in cli_artifact_pre_run and cli_artifact_run
		["download-artifact"]="artifact"         # implemented in cli_artifact_pre_run and cli_artifact_run

		# shortcuts, see vars set below. the use legacy single build, and try to control it via variables
		["rootfs"]="artifact"

		["kernel"]="artifact"
		["kernel-dtb"]="artifact"
		["kernel-patch"]="artifact"
		["kernel-config"]="artifact"
		["rewrite-kernel-config"]="artifact"

		# Patch kernel and then check & validate the dtb file
		["dts-check"]="artifact" # Not really an artifact, but cli output only. Builds nothing.

		["uboot"]="artifact"
		["uboot-patch"]="artifact"
		["atf-patch"]="artifact"
		["crust-patch"]="artifact"
		["uboot-config"]="artifact"

		["firmware"]="artifact"
		["firmware-full"]="artifact"
		["armbian-config"]="artifact"
		["armbian-zsh"]="artifact"
		["armbian-plymouth-theme"]="artifact"
		["fake-ubuntu-advantage-tools"]="artifact"

		["armbian-base-files"]="artifact"
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

		# repo pipeline stuff is usually run on saved/restored artifacts for output/info, so don't clean them by default
		["debs-to-repo-download"]="CLEAN_MATRIX='no' CLEAN_INFO='no'"
		["debs-to-repo-reprepro"]="CLEAN_MATRIX='no' CLEAN_INFO='no'"

		# inventory
		["inventory-boards"]="TARGETS_FILE='something_that_does_not_exist_so_defaults_are_used'"

		# patching
		["rewrite-kernel-patches"]="REWRITE_PATCHES='yes'" # rewrite the patches after round-tripping to git: "rebase patches"
		["rewrite-uboot-patches"]="REWRITE_PATCHES='yes'"  # rewrite the patches after round-tripping to git: "rebase patches"
		["rewrite-kernel-patches-needing-rebase"]="REWRITE_PATCHES='yes' REWRITE_PATCHES_NEEDING_REBASE='yes'"
		["rewrite-uboot-patches-needing-rebase"]="REWRITE_PATCHES='yes' REWRITE_PATCHES_NEEDING_REBASE='yes'"

		# artifact shortcuts
		["rootfs"]="WHAT='rootfs' ${common_cli_artifact_vars}"

		["kernel"]="WHAT='kernel' ${common_cli_artifact_vars}"
		["kernel-config"]="WHAT='kernel' KERNEL_CONFIGURE='yes' ${common_cli_artifact_interactive_vars} ${common_cli_artifact_vars}"
		["rewrite-kernel-config"]="WHAT='kernel' KERNEL_CONFIGURE='yes' ARTIFACT_WILL_NOT_BUILD='yes' ARTIFACT_IGNORE_CACHE='yes' ${common_cli_artifact_vars}"
		["kernel-patch"]="WHAT='kernel' CREATE_PATCHES='yes' ${common_cli_artifact_interactive_vars} ${common_cli_artifact_vars}"
		["kernel-dtb"]="WHAT='kernel' KERNEL_DTB_ONLY='yes' ${common_cli_artifact_interactive_vars} ${common_cli_artifact_vars}"
		["dts-check"]="WHAT='kernel' DTS_VALIDATE='yes' ARTIFACT_WILL_NOT_BUILD='yes' ARTIFACT_IGNORE_CACHE='yes'" # Not really an artifact, but cli output only. Builds nothing.

		["uboot"]="WHAT='uboot' ${common_cli_artifact_vars}"
		["uboot-config"]="WHAT='uboot' UBOOT_CONFIGURE='yes' ${common_cli_artifact_interactive_vars} ${common_cli_artifact_vars}"
		["uboot-patch"]="WHAT='uboot' CREATE_PATCHES='yes' ${common_cli_artifact_interactive_vars} ${common_cli_artifact_vars}"
		["atf-patch"]="WHAT='uboot' CREATE_PATCHES_ATF='yes' ${common_cli_artifact_interactive_vars} ${common_cli_artifact_vars}"
		["crust-patch"]="WHAT='uboot' CREATE_PATCHES_CRUST='yes' ${common_cli_artifact_interactive_vars} ${common_cli_artifact_vars}"

		["firmware"]="WHAT='firmware' ${common_cli_artifact_vars}"
		["firmware-full"]="WHAT='full_firmware' ${common_cli_artifact_vars}"
		["armbian-config"]="WHAT='armbian-config' ${common_cli_artifact_vars}"
		["armbian-zsh"]="WHAT='armbian-zsh' ${common_cli_artifact_vars}"
		["armbian-plymouth-theme"]="WHAT='armbian-plymouth-theme' ${common_cli_artifact_vars}"
		["fake-ubuntu-advantage-tools"]="WHAT='fake_ubuntu_advantage_tools' ${common_cli_artifact_vars}"

		["armbian-base-files"]="WHAT='armbian-base-files' ${common_cli_artifact_vars}"
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
