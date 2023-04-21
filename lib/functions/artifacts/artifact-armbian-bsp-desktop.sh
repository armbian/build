#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function artifact_armbian-bsp-desktop_config_dump() {
	artifact_input_variables[RELEASE]="${RELEASE}"
	artifact_input_variables[BOARD]="${BOARD}"
	artifact_input_variables[BRANCH]="${BRANCH}"

	# @TODO: this should not be true... but is.
	artifact_input_variables[DESKTOP_ENVIRONMENT]="${DESKTOP_ENVIRONMENT}"
	artifact_input_variables[DESKTOP_ENVIRONMENT_CONFIG_NAME]="${DESKTOP_ENVIRONMENT_CONFIG_NAME}"
}

function artifact_armbian-bsp-desktop_prepare_version() {
	: "${artifact_prefix_version:?artifact_prefix_version is not set}"
	: "${BRANCH:?BRANCH is not set}"
	: "${BOARD:?BOARD is not set}"
	: "${RELEASE:?RELEASE is not set}"

	# @TODO: this should not be true... but is.
	: "${DESKTOP_ENVIRONMENT:?DESKTOP_ENVIRONMENT is not set}"
	: "${DESKTOP_ENVIRONMENT_CONFIG_NAME:?DESKTOP_ENVIRONMENT_CONFIG_NAME is not set}"

	artifact_version="undetermined"        # outer scope
	artifact_version_reason="undetermined" # outer scope

	declare short_hash_size=4

	declare fake_unchanging_base_version="1"

	# @TODO: hash copy_all_packages_files_for "bsp-desktop"

	# get the hashes of the lib/ bash sources involved...
	declare hash_files="undetermined"
	calculate_hash_for_files "${SRC}"/lib/functions/bsp/armbian-bsp-desktop-deb.sh
	declare bash_hash="${hash_files}"
	declare bash_hash_short="${bash_hash:0:${short_hash_size}}"

	# outer scope
	artifact_version="${artifact_prefix_version}${fake_unchanging_base_version}-B${bash_hash_short}"

	declare -a reasons=(
		"Armbian armbian-bsp-desktop"
		"framework bash hash \"${bash_hash}\""
	)

	artifact_version_reason="${reasons[*]}" # outer scope

	artifact_name="armbian-bsp-desktop-${BOARD}-${BRANCH}"
	artifact_type="deb"
	artifact_base_dir="${DEB_STORAGE}/${RELEASE}"
	artifact_final_file="${DEB_STORAGE}/${RELEASE}/${artifact_name}_${artifact_version}_${ARCH}.deb"

	artifact_map_packages=(
		["armbian-bsp-desktop"]="${artifact_name}"
	)

	artifact_map_debs=(
		["armbian-bsp-desktop"]="${RELEASE}/${artifact_name}_${artifact_version}_${ARCH}.deb"
	)

	return 0
}

function artifact_armbian-bsp-desktop_build_from_sources() {
	LOG_SECTION="compile_armbian-bsp-desktop" do_with_logging compile_armbian-bsp-desktop
}

function artifact_armbian-bsp-desktop_cli_adapter_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function artifact_armbian-bsp-desktop_cli_adapter_config_prep() {
	: "${RELEASE:?RELEASE is not set}"
	: "${BOARD:?BOARD is not set}"

	# @TODO: this should not be true... but is.
	: "${DESKTOP_ENVIRONMENT:?DESKTOP_ENVIRONMENT is not set}"
	: "${DESKTOP_ENVIRONMENT_CONFIG_NAME:?DESKTOP_ENVIRONMENT_CONFIG_NAME is not set}"

	# this requires aggregation, and thus RELEASE, but also everything else.
	declare -g artifact_version_requires_aggregation="yes"
	use_board="yes" allow_no_family="no" skip_kernel="no" prep_conf_main_only_rootfs_ni < /dev/null # no stdin for this, so it bombs if tries to be interactive.
}

function artifact_armbian-bsp-desktop_get_default_oci_target() {
	artifact_oci_target_base="${GHCR_SOURCE}/armbian/cache-packages/"
}

function artifact_armbian-bsp-desktop_is_available_in_local_cache() {
	is_artifact_available_in_local_cache
}

function artifact_armbian-bsp-desktop_is_available_in_remote_cache() {
	is_artifact_available_in_remote_cache
}

function artifact_armbian-bsp-desktop_obtain_from_remote_cache() {
	obtain_artifact_from_remote_cache
}

function artifact_armbian-bsp-desktop_deploy_to_remote_cache() {
	upload_artifact_to_oci
}
