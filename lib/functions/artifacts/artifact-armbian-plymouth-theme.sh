#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function artifact_armbian-plymouth-theme_config_dump() {
	# artifact_input_variables: None, for armbian-plymouth-theme.
	:
}

function artifact_armbian-plymouth-theme_prepare_version() {
	artifact_version="undetermined"        # outer scope
	artifact_version_reason="undetermined" # outer scope

	declare short_hash_size=4

	declare fake_unchanging_base_version="1"

	# get the hashes of the lib/ bash sources involved...
	declare hash_files="undetermined"
	calculate_hash_for_files "${SRC}"/lib/functions/compilation/packages/armbian-plymouth-theme-deb.sh
	declare bash_hash="${hash_files}"
	declare bash_hash_short="${bash_hash:0:${short_hash_size}}"

	# outer scope
	artifact_version="${artifact_prefix_version}-B${bash_hash_short}"

	declare -a reasons=(
		"Armbian armbian-plymouth-theme"
		"framework bash hash \"${bash_hash}\""
	)

	artifact_version_reason="${reasons[*]}" # outer scope

	artifact_map_packages=(
		["armbian-plymouth-theme"]="armbian-plymouth-theme"
	)

	artifact_map_debs=(
		["armbian-plymouth-theme"]="armbian-plymouth-theme_${artifact_version}_all.deb"
	)

	artifact_name="armbian-plymouth-theme"
	artifact_type="deb"
	artifact_base_dir="${DEB_STORAGE}"
	artifact_final_file="${DEB_STORAGE}/armbian-plymouth-theme_${artifact_version}_all.deb"

	return 0
}

function artifact_armbian-plymouth-theme_build_from_sources() {
	LOG_SECTION="compile_armbian-plymouth-theme" do_with_logging compile_armbian-plymouth-theme
}

function artifact_armbian-plymouth-theme_cli_adapter_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function artifact_armbian-plymouth-theme_cli_adapter_config_prep() {
	use_board="no" prep_conf_main_minimal_ni < /dev/null # no stdin for this, so it bombs if tries to be interactive.
}

function artifact_armbian-plymouth-theme_get_default_oci_target() {
	artifact_oci_target_base="${GHCR_SOURCE}/armbian/os/"
}

function artifact_armbian-plymouth-theme_is_available_in_local_cache() {
	is_artifact_available_in_local_cache
}

function artifact_armbian-plymouth-theme_is_available_in_remote_cache() {
	is_artifact_available_in_remote_cache
}

function artifact_armbian-plymouth-theme_obtain_from_remote_cache() {
	obtain_artifact_from_remote_cache
}

function artifact_armbian-plymouth-theme_deploy_to_remote_cache() {
	upload_artifact_to_oci
}
