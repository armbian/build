#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function artifact_armbian-desktop_config_dump() {
	artifact_input_variables[RELEASE]="${RELEASE}"
	artifact_input_variables[DESKTOP_ENVIRONMENT]="${DESKTOP_ENVIRONMENT}"
}

function artifact_armbian-desktop_prepare_version() {
	: "${artifact_prefix_version:?artifact_prefix_version is not set}"
	: "${RELEASE:?RELEASE is not set}"

	: "${DESKTOP_ENVIRONMENT:?DESKTOP_ENVIRONMENT is not set}"
	: "${DESKTOP_ENVIRONMENT_CONFIG_NAME:?DESKTOP_ENVIRONMENT_CONFIG_NAME is not set}" # Not keyed, but required.

	artifact_version="undetermined"        # outer scope
	artifact_version_reason="undetermined" # outer scope

	declare short_hash_size=4

	declare fake_unchanging_base_version="1"

	# Hash variables that affect the contents of desktop package
	declare -a vars_to_hash=(
		"${AGGREGATED_DESKTOP_POSTINST}"
		"${AGGREGATED_DESKTOP_CREATE_DESKTOP_PACKAGE}"
		"${AGGREGATED_PACKAGES_DESKTOP_COMMA}"
	)
	declare hash_vars="undetermined"
	hash_vars="$(echo "${vars_to_hash[@]}" | sha256sum | cut -d' ' -f1)"
	vars_config_hash="${hash_vars}"
	declare var_config_hash_short="${vars_config_hash:0:${short_hash_size}}"

	# get the hashes of the lib/ bash sources involved...
	declare hash_files="undetermined"
	calculate_hash_for_files "${SRC}"/lib/functions/compilation/packages/armbian-desktop-deb.sh
	declare bash_hash="${hash_files}"
	declare bash_hash_short="${bash_hash:0:${short_hash_size}}"

	# outer scope
	artifact_version="${artifact_prefix_version}${fake_unchanging_base_version}-V${var_config_hash_short}-B${bash_hash_short}"

	declare -a reasons=(
		"Armbian armbian-desktop"
		"vars hash \"${vars_config_hash}\""
		"framework bash hash \"${bash_hash}\""
	)

	artifact_version_reason="${reasons[*]}" # outer scope

	artifact_name="armbian-${RELEASE}-desktop-${DESKTOP_ENVIRONMENT}"
	artifact_type="deb"
	artifact_base_dir="${DEB_STORAGE}/${RELEASE}"
	artifact_final_file="${DEB_STORAGE}/${RELEASE}/${artifact_name}_${artifact_version}_all.deb"

	artifact_map_packages=(
		["armbian-desktop"]="${artifact_name}"
	)

	artifact_map_debs=(
		["armbian-desktop"]="${RELEASE}/${artifact_name}_${artifact_version}_all.deb"
	)

	return 0
}

function artifact_armbian-desktop_build_from_sources() {
	LOG_SECTION="compile_armbian-desktop" do_with_logging compile_armbian-desktop
}

function artifact_armbian-desktop_cli_adapter_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function artifact_armbian-desktop_cli_adapter_config_prep() {
	: "${RELEASE:?RELEASE is not set}"
	: "${DESKTOP_ENVIRONMENT:?DESKTOP_ENVIRONMENT is not set}"
	: "${DESKTOP_ENVIRONMENT_CONFIG_NAME:?DESKTOP_ENVIRONMENT_CONFIG_NAME is not set}"

	# this requires aggregation, and thus RELEASE, but also everything else.
	declare -g artifact_version_requires_aggregation="yes"
	use_board="yes" allow_no_family="no" skip_kernel="no" prep_conf_main_only_rootfs_ni < /dev/null # no stdin for this, so it bombs if tries to be interactive.
}

function artifact_armbian-desktop_get_default_oci_target() {
	artifact_oci_target_base="${GHCR_SOURCE}/armbian/cache-packages/"
}

function artifact_armbian-desktop_is_available_in_local_cache() {
	is_artifact_available_in_local_cache
}

function artifact_armbian-desktop_is_available_in_remote_cache() {
	is_artifact_available_in_remote_cache
}

function artifact_armbian-desktop_obtain_from_remote_cache() {
	obtain_artifact_from_remote_cache
}

function artifact_armbian-desktop_deploy_to_remote_cache() {
	upload_artifact_to_oci
}
