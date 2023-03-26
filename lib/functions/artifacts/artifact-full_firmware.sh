#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function artifact_full_firmware_prepare_version() {
	artifact_version="undetermined"        # outer scope
	artifact_version_reason="undetermined" # outer scope
	[[ -z "${artifact_prefix_version}" ]] && exit_with_error "artifact_prefix_version is not set"

	local ARMBIAN_FIRMWARE_SOURCE="${ARMBIAN_FIRMWARE_GIT_SOURCE:-"https://github.com/armbian/firmware"}"
	local ARMBIAN_FIRMWARE_BRANCH="branch:${ARMBIAN_FIRMWARE_GIT_BRANCH:-"master"}"

	debug_var ARMBIAN_FIRMWARE_SOURCE
	debug_var ARMBIAN_FIRMWARE_BRANCH
	debug_var MAINLINE_FIRMWARE_SOURCE

	declare short_hash_size=4

	declare -A GIT_INFO_ARMBIAN_FIRMWARE=([GIT_SOURCE]="${ARMBIAN_FIRMWARE_SOURCE}" [GIT_REF]="${ARMBIAN_FIRMWARE_BRANCH}")
	run_memoized GIT_INFO_ARMBIAN_FIRMWARE "git2info" memoized_git_ref_to_info
	debug_dict GIT_INFO_ARMBIAN_FIRMWARE

	declare -A GIT_INFO_MAINLINE_FIRMWARE=([GIT_SOURCE]="${MAINLINE_FIRMWARE_SOURCE}" [GIT_REF]="branch:main")
	run_memoized GIT_INFO_MAINLINE_FIRMWARE "git2info" memoized_git_ref_to_info
	debug_dict GIT_INFO_MAINLINE_FIRMWARE

	declare fake_unchanging_base_version="1"

	declare short_sha1="${GIT_INFO_ARMBIAN_FIRMWARE[SHA1]:0:${short_hash_size}}"
	declare short_sha1_mainline="${GIT_INFO_MAINLINE_FIRMWARE[SHA1]:0:${short_hash_size}}"

	# get the hashes of the lib/ bash sources involved...
	declare hash_files="undetermined"
	calculate_hash_for_files "${SRC}"/lib/functions/compilation/packages/firmware-deb.sh
	declare bash_hash="${hash_files}"
	declare bash_hash_short="${bash_hash:0:${short_hash_size}}"

	# outer scope
	artifact_version="${artifact_prefix_version}${fake_unchanging_base_version}-SA${short_sha1}-SM${short_sha1_mainline}-B${bash_hash_short}"

	declare -a reasons=(
		"Armbian firmware git revision \"${GIT_INFO_ARMBIAN_FIRMWARE[SHA1]}\""
		"Mainline firmware git revision \"${GIT_INFO_MAINLINE_FIRMWARE[SHA1]}\""
		"framework bash hash \"${bash_hash}\""
	)

	artifact_version_reason="${reasons[*]}" # outer scope

	artifact_map_packages=(
		["armbian-firmware-full"]="armbian-firmware-full"
	)

	artifact_map_debs=(
		["armbian-firmware-full"]="armbian-firmware-full_${artifact_version}_all.deb"
	)

	artifact_name="armbian-firmware-full"
	artifact_type="deb"
	artifact_base_dir="${DEB_STORAGE}"
	artifact_final_file="${DEB_STORAGE}/armbian-firmware-full_${artifact_version}_all.deb"

	return 0
}

function artifact_full_firmware_build_from_sources() {
	FULL="-full" REPLACE="" LOG_SECTION="compile_firmware_full" do_with_logging compile_firmware
}

function artifact_full_firmware_cli_adapter_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function artifact_full_firmware_cli_adapter_config_prep() {
	use_board="no" prep_conf_main_minimal_ni < /dev/null # no stdin for this, so it bombs if tries to be interactive.
}

function artifact_full_firmware_get_default_oci_target() {
	artifact_oci_target_base="ghcr.io/armbian/cache-firmware/"
}

function artifact_full_firmware_is_available_in_local_cache() {
	is_artifact_available_in_local_cache
}

function artifact_full_firmware_is_available_in_remote_cache() {
	is_artifact_available_in_remote_cache
}

function artifact_full_firmware_obtain_from_remote_cache() {
	obtain_artifact_from_remote_cache
}

function artifact_full_firmware_deploy_to_remote_cache() {
	upload_artifact_to_oci
}
