#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function artifact_armbian-bsp-generic_config_dump() {
	artifact_input_variables[RELEASE]="${RELEASE}"
	artifact_input_variables[BRANCH]="${BRANCH}"
}

function artifact_armbian-bsp-generic_prepare_version() {
	: "${BRANCH:?BRANCH is not set}"

	artifact_version="undetermined"        # outer scope
	artifact_version_reason="undetermined" # outer scope

	declare short_hash_size=4

	declare fake_unchanging_base_version="1"

	# Generic package has no board/family hooks
	declare hash_hooks_short="0000"

	# Hash variables that affect the contents of bsp-generic package.
	# Those contain /armbian a lot, so don't normalize them.
	declare -a vars_to_hash_no_normalize=()
	declare hash_variables="undetermined"                                                     # will be set by calculate_hash_for_variables(), but without normalization
	do_normalize_src_path="no" calculate_hash_for_variables "${vars_to_hash_no_normalize[@]}" # don't normalize
	declare hash_vars_no_normalize="${hash_variables}"

	declare -a vars_to_hash=(
		"KEEP_ORIGINAL_OS_RELEASE: ${KEEP_ORIGINAL_OS_RELEASE:-"no"}" # /etc/os-release
		"IMAGE_TYPE: ${IMAGE_TYPE}"                                   # /etc/armbian-release
		"hash_vars_no_normalize: ${hash_vars_no_normalize}"           # The non-normalized part, above
	)
	declare hash_variables="undetermined" # will be set by calculate_hash_for_variables(), which normalizes the input
	calculate_hash_for_variables "${vars_to_hash[@]}"
	declare vars_config_hash="${hash_variables}"
	declare var_config_hash_short="${vars_config_hash:0:${short_hash_size}}"

	declare -a dirs_to_hash=(
		"${SRC}/packages/bsp/common" # common stuff
		"${SRC}/config/optional/_any_board/_packages/bsp-generic"
	)
	declare hash_files="undetermined"
	calculate_hash_for_all_files_in_dirs "${dirs_to_hash[@]}"
	packages_config_hash="${hash_files}"
	declare packages_config_hash_short="${packages_config_hash:0:${short_hash_size}}"

	# get the hashes of the lib/ bash sources involved...
	declare hash_files="undetermined"
	#FIXME: do we need to fork bsp/armbian-bsp-cli-deb.sh ?
	calculate_hash_for_bash_deb_artifact "bsp/armbian-bsp-cli-deb.sh" "bsp/utils-bsp.sh"
	declare bash_hash="${hash_files}"
	declare bash_hash_short="${bash_hash:0:${short_hash_size}}"

	# outer scope
	artifact_version="${fake_unchanging_base_version}-PC${packages_config_hash_short}-V${var_config_hash_short}-H${hash_hooks_short}-B${bash_hash_short}"

	declare -a reasons=(
		"Armbian package armbian-bsp-generic"
		"BRANCH \"${BRANCH}\""
		"Packages and config files hash \"${packages_config_hash}\""
		"Hooks hash \"${hash_hooks}\""
		"Variables/bootscripts hash \"${vars_config_hash}\""
		"framework bash hash \"${bash_hash}\""
	)

	artifact_version_reason="${reasons[*]}" # outer scope

	artifact_deb_repo="global"  # "global" meaning: release-independent repo. could be '${RELEASE}' for a release-specific package.
	artifact_deb_arch="all"     # arch-specific package, or 'all' for arch-independent package.
	#FIXME: BRANCH for sure, RELEASE maybe?
	artifact_name="armbian-bsp-generic-${BRANCH}"
	artifact_type="deb-tar"

	artifact_map_packages=(["armbian-bsp-generic"]="${artifact_name}")

	# Register the function used to re-version the _contents_ of the bsp-cli deb file (non-transitional)
	# FIXME: can we live without this?
	#artifact_debs_reversion_functions+=("reversion_armbian-bsp-generic_deb_contents")

	# there is no transitional package, this is just boilerplate
	#if artifact_armbian-bsp-generic_needs_transitional_package; then
	#	artifact_map_packages+=(["armbian-bsp-generic-transitional"]="armbian-bsp-generic-${BOARD}${EXTRA_BSP_NAME}")
	#	# Register the function used to re-version the _contents_ of the bsp-cli deb file (transitional)
	#	artifact_debs_reversion_functions+=("reversion_armbian-bsp-generic-transitional_deb_contents")
	#fi

	return 0
}

function artifact_armbian-bsp-generic_build_from_sources() {
	LOG_SECTION="compile_armbian-bsp-generic" do_with_logging compile_armbian-bsp-generic

	# Generate transitional package when needed.
	if artifact_armbian-bsp-generic_needs_transitional_package; then
		: # we don't have this hook, it's just boilerplate
		#LOG_SECTION="compile_armbian-bsp-generic" do_with_logging compile_armbian-bsp-generic-transitional
	fi
}

function artifact_armbian-bsp-generic_cli_adapter_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function artifact_armbian-bsp-generic_cli_adapter_config_prep() {
	# there is no need for aggregation here.
	use_board="no" allow_no_family="yes" skip_kernel="no" prep_conf_main_minimal_ni < /dev/null # no stdin for this, so it bombs if tries to be interactive.
}

function artifact_armbian-bsp-generic_get_default_oci_target() {
	artifact_oci_target_base="${GHCR_SOURCE}/armbian/os/"
}

function artifact_armbian-bsp-generic_is_available_in_local_cache() {
	is_artifact_available_in_local_cache
}

function artifact_armbian-bsp-generic_is_available_in_remote_cache() {
	is_artifact_available_in_remote_cache
}

function artifact_armbian-bsp-generic_obtain_from_remote_cache() {
	obtain_artifact_from_remote_cache
}

function artifact_armbian-bsp-generic_deploy_to_remote_cache() {
	upload_artifact_to_oci
}

function artifact_armbian-bsp-generic_needs_transitional_package() {
	return 1 # we're too new to need a transitional package. Note that this follows the C/bash errno convention where 0 is true
	# see equivalent for artifact_armbian-bsp-cli
}
