#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function artifact_firmware_config_dump() {
	# artifact_input_variables: None, for firmware.
	:
}

function artifact_firmware_prepare_version() {
	artifact_version="undetermined"        # outer scope
	artifact_version_reason="undetermined" # outer scope

	local ARMBIAN_FIRMWARE_SOURCE="${ARMBIAN_FIRMWARE_GIT_SOURCE:-"https://github.com/armbian/firmware"}"
	local ARMBIAN_FIRMWARE_BRANCH="branch:${ARMBIAN_FIRMWARE_GIT_BRANCH:-"master"}"

	debug_var ARMBIAN_FIRMWARE_SOURCE
	debug_var ARMBIAN_FIRMWARE_BRANCH

	declare short_hash_size=4

	declare -A GIT_INFO_ARMBIAN_FIRMWARE=([GIT_SOURCE]="${ARMBIAN_FIRMWARE_SOURCE}" [GIT_REF]="${ARMBIAN_FIRMWARE_BRANCH}")
	run_memoized GIT_INFO_ARMBIAN_FIRMWARE "git2info" memoized_git_ref_to_info
	debug_dict GIT_INFO_ARMBIAN_FIRMWARE

	# Sanity check, the SHA1 gotta be sane.
	[[ "${GIT_INFO_ARMBIAN_FIRMWARE[SHA1]}" =~ ^[0-9a-f]{40}$ ]] || exit_with_error "SHA1 is not sane: '${GIT_INFO_ARMBIAN_FIRMWARE[SHA1]}'"

	declare fake_unchanging_base_version="1"

	declare short_sha1="${GIT_INFO_ARMBIAN_FIRMWARE[SHA1]:0:${short_hash_size}}"

	# get the hashes of the lib/ bash sources involved...
	declare hash_files="undetermined"
	calculate_hash_for_bash_deb_artifact "compilation/packages/firmware-deb.sh"
	declare bash_hash="${hash_files}"
	declare bash_hash_short="${bash_hash:0:${short_hash_size}}"

	# outer scope
	artifact_version="${fake_unchanging_base_version}-SA${short_sha1}-B${bash_hash_short}"

	declare -a reasons=(
		"Armbian firmware git revision \"${GIT_INFO_ARMBIAN_FIRMWARE[SHA1]}\""
		"framework bash hash \"${bash_hash}\""
	)

	artifact_version_reason="${reasons[*]}" # outer scope

	artifact_map_packages=(["armbian-firmware"]="armbian-firmware")

	artifact_name="armbian-firmware"
	artifact_type="deb"
	artifact_deb_repo="global"
	artifact_deb_arch="all"

	return 0
}

function artifact_firmware_build_from_sources() {
	FULL="" REPLACE="-full" LOG_SECTION="compile_firmware" do_with_logging compile_firmware
}

function artifact_firmware_cli_adapter_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function artifact_firmware_cli_adapter_config_prep() {
	use_board="no" prep_conf_main_minimal_ni < /dev/null # no stdin for this, so it bombs if tries to be interactive.
}

function artifact_firmware_get_default_oci_target() {
	artifact_oci_target_base="${GHCR_SOURCE}/armbian/os/"
}

function artifact_firmware_is_available_in_local_cache() {
	is_artifact_available_in_local_cache
}

function artifact_firmware_is_available_in_remote_cache() {
	is_artifact_available_in_remote_cache
}

function artifact_firmware_obtain_from_remote_cache() {
	obtain_artifact_from_remote_cache
}

function artifact_firmware_deploy_to_remote_cache() {
	upload_artifact_to_oci
}
