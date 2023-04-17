#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function artifact_fake_ubuntu_advantage_tools_config_dump() {
	# artifact_input_variables: None, for fake ubuntu advantage.
	:
}

function artifact_fake_ubuntu_advantage_tools_prepare_version() {
	artifact_version="undetermined"        # outer scope
	artifact_version_reason="undetermined" # outer scope

	declare short_hash_size=4

	declare fake_unchanging_base_version="1"

	# get the hashes of the lib/ bash sources involved...
	declare hash_files="undetermined"
	calculate_hash_for_files "${SRC}"/lib/functions/compilation/packages/fake_ubuntu_advantage_tools-deb.sh
	declare bash_hash="${hash_files}"
	declare bash_hash_short="${bash_hash:0:${short_hash_size}}"

	# outer scope
	artifact_version="${artifact_prefix_version}${fake_unchanging_base_version}-B${bash_hash_short}"

	declare -a reasons=(
		"Armbian fake-ubuntu-advantage-tools"
		"framework bash hash \"${bash_hash}\""
	)

	artifact_version_reason="${reasons[*]}" # outer scope

	artifact_map_packages=(
		["fake-ubuntu-advantage-tools"]="fake-ubuntu-advantage-tools"
	)

	artifact_map_debs=(
		["fake-ubuntu-advantage-tools"]="fake-ubuntu-advantage-tools_${artifact_version}_all.deb"
	)

	artifact_name="fake-ubuntu-advantage-tools"
	artifact_type="deb"
	artifact_base_dir="${DEB_STORAGE}"
	artifact_final_file="${DEB_STORAGE}/fake-ubuntu-advantage-tools_${artifact_version}_all.deb"

	return 0
}

function artifact_fake_ubuntu_advantage_tools_build_from_sources() {
	LOG_SECTION="compile_fake_ubuntu_advantage_tools" do_with_logging compile_fake_ubuntu_advantage_tools
}

function artifact_fake_ubuntu_advantage_tools_cli_adapter_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function artifact_fake_ubuntu_advantage_tools_cli_adapter_config_prep() {
	use_board="no" prep_conf_main_minimal_ni < /dev/null # no stdin for this, so it bombs if tries to be interactive.
}

function artifact_fake_ubuntu_advantage_tools_get_default_oci_target() {
	artifact_oci_target_base="${GHCR_SOURCE}/armbian/cache-packages/"
}

function artifact_fake_ubuntu_advantage_tools_is_available_in_local_cache() {
	is_artifact_available_in_local_cache
}

function artifact_fake_ubuntu_advantage_tools_is_available_in_remote_cache() {
	is_artifact_available_in_remote_cache
}

function artifact_fake_ubuntu_advantage_tools_obtain_from_remote_cache() {
	obtain_artifact_from_remote_cache
}

function artifact_fake_ubuntu_advantage_tools_deploy_to_remote_cache() {
	upload_artifact_to_oci
}
