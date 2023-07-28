#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function artifact_rootfs_config_dump() {
	artifact_input_variables[ARCH]="${ARCH}"
	artifact_input_variables[RELEASE]="${RELEASE}"
	artifact_input_variables[SELECTED_CONFIGURATION]="${SELECTED_CONFIGURATION}" # should be represented below anyway
	artifact_input_variables[BUILD_MINIMAL]="${BUILD_MINIMAL}"
	artifact_input_variables[DESKTOP_ENVIRONMENT]="${DESKTOP_ENVIRONMENT:-"no_DESKTOP_ENVIRONMENT_set"}"
	artifact_input_variables[DESKTOP_ENVIRONMENT_CONFIG_NAME]="${DESKTOP_ENVIRONMENT_CONFIG_NAME:-"no_DESKTOP_ENVIRONMENT_CONFIG_NAME_set"}"
	artifact_input_variables[DESKTOP_APPGROUPS_SELECTED]="${DESKTOP_APPGROUPS_SELECTED:-"no_DESKTOP_APPGROUPS_SELECTED_set"}"
	# Hash of the packages added/removed by extensions
	declare pkgs_hash="undetermined"
	pkgs_hash="$(echo "${REMOVE_PACKAGES[*]} ${EXTRA_PACKAGES_ROOTFS[*]} ${PACKAGE_LIST_BOARD_REMOVE} ${PACKAGE_LIST_FAMILY_REMOVE}" | sha256sum | cut -d' ' -f1)"
	artifact_input_variables[EXTRA_PKG_ADD_REMOVE_HASH]="${pkgs_hash}"
}

function artifact_rootfs_prepare_version() {
	artifact_version="undetermined"        # outer scope
	artifact_version_reason="undetermined" # outer scope

	assert_requires_aggregation # Bombs if aggregation has not run

	declare -g rootfs_cache_id="none_yet"

	calculate_rootfs_cache_id # sets rootfs_cache_id

	display_alert "rootfs version" "packages_hash: '${packages_hash:-}' cache_type: '${cache_type:-}' rootfs_cache_id: '${rootfs_cache_id}'" "info"

	declare -a reasons=(
		"arch \"${ARCH}\""
		"release \"${RELEASE}\""
		"type \"${cache_type}\""
		"cache_id \"${rootfs_cache_id}\""
	)

	# add more reasons for desktop stuff
	if [[ "${DESKTOP_ENVIRONMENT}" != "" ]]; then
		reasons+=("desktop_environment \"${DESKTOP_ENVIRONMENT}\"")
		reasons+=("desktop_environment_config_name \"${DESKTOP_ENVIRONMENT_CONFIG_NAME}\"")
		reasons+=("desktop_appgroups_selected \"${DESKTOP_APPGROUPS_SELECTED}\"")
	fi

	# we use YYYYMM to make a new rootfs cache version per-month, even if nothing else changes.
	declare yyyymm="undetermined"
	yyyymm="$(date +%Y%m)"

	# outer scope
	artifact_version="${yyyymm}-${rootfs_cache_id}"
	artifact_version_reason="${reasons[*]}"
	artifact_name="rootfs-${ARCH}-${RELEASE}-${cache_type}"
	artifact_type="tar.zst"
	artifact_base_dir="${SRC}/cache/rootfs"
	artifact_final_file="${SRC}/cache/rootfs/${artifact_name}_${artifact_version}.tar.zst"

	return 0
}

function artifact_rootfs_build_from_sources() {
	debug_var artifact_final_file
	debug_var artifact_final_file_basename

	# Creates a cleanup handler 'trap_handler_cleanup_rootfs_and_image'
	LOG_SECTION="prepare_rootfs_build_params_and_trap" do_with_logging prepare_rootfs_build_params_and_trap

	debug_var artifact_final_file
	debug_var artifact_final_file_basename

	# validate that tmpfs_estimated_size is set and higher than zero, or exit_with_error
	[[ -z ${tmpfs_estimated_size} ]] && exit_with_error "tmpfs_estimated_size is not set"
	[[ ${tmpfs_estimated_size} -le 0 ]] && exit_with_error "tmpfs_estimated_size is not higher than zero"

	# "rootfs" CLI skips over a lot goes straight to create the rootfs. It doesn't check cache etc.
	LOG_SECTION="create_new_rootfs_cache" do_with_logging create_new_rootfs_cache

	debug_var artifact_final_file
	debug_var artifact_final_file_basename
	debug_var cache_name
	debug_var cache_fname

	if [[ ! -f "${artifact_final_file}" ]]; then
		exit_with_error "Rootfs cache file '${artifact_final_file}' does not exist after create_new_rootfs_cache()."
	else
		display_alert "Rootfs cache file '${artifact_final_file}' exists after create_new_rootfs_cache()." "YESSS" "debug"
	fi

	# obtain the size, in MiB, of "${SDCARD}" at this point.
	declare -i rootfs_size_mib
	rootfs_size_mib=$(du -sm "${SDCARD}" | awk '{print $1}')
	display_alert "Actual rootfs size" "${rootfs_size_mib}MiB after basic/cache" ""

	# warn if rootfs_size_mib is higher than the tmpfs_estimated_size
	if [[ ${rootfs_size_mib} -gt ${tmpfs_estimated_size} ]]; then
		display_alert "Rootfs actual size is larger than estimated tmpfs size after basic/cache" "${rootfs_size_mib}MiB > ${tmpfs_estimated_size}MiB" "wrn"
	fi

	# Run the cleanup handler.
	execute_and_remove_cleanup_handler trap_handler_cleanup_rootfs_and_image

	return 0
}

function artifact_rootfs_cli_adapter_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function artifact_rootfs_cli_adapter_config_prep() {
	declare -g artifact_version_requires_aggregation="yes"
	declare -g ROOTFS_COMPRESSION_RATIO="${ROOTFS_COMPRESSION_RATIO:-"15"}" # default to Compress stronger when we make rootfs cache

	# If BOARD is set, use it to convert to an ARCH.
	if [[ -n ${BOARD} ]]; then
		display_alert "BOARD is set, converting to ARCH for rootfs building" "'BOARD=${BOARD}'" "info"
		# Convert BOARD to ARCH; source the BOARD and FAMILY stuff
		LOG_SECTION="config_source_board_file" do_with_conditional_logging config_source_board_file
		LOG_SECTION="source_family_config_and_arch" do_with_conditional_logging source_family_config_and_arch
		display_alert "Done sourcing board file" "'${BOARD}' - arch: '${ARCH}'" "info"
	fi

	declare -a vars_need_to_be_set=("RELEASE" "ARCH")
	# loop through all vars and check if they are not set and bomb out if so
	for var in "${vars_need_to_be_set[@]}"; do
		if [[ -z ${!var} ]]; then
			exit_with_error "Param '${var}' is not set but needs to be set for rootfs CLI."
		fi
	done

	declare -r __wanted_rootfs_arch="${ARCH}"
	declare -g -r RELEASE="${RELEASE}" # make readonly for finding who tries to change it
	declare -g -r NEEDS_BINFMT="yes"   # make sure binfmts are installed during prepare_host_interactive

	# prep_conf_main_only_rootfs_ni is prep_conf_main_only_rootfs_ni() + mark_aggregation_required_in_default_build_start()
	prep_conf_main_only_rootfs_ni < /dev/null # no stdin for this, so it bombs if tries to be interactive.

	declare -g -r ARCH="${ARCH}" # make readonly for finding who tries to change it
	if [[ "${ARCH}" != "${__wanted_rootfs_arch}" ]]; then
		exit_with_error "Param 'ARCH' is set to '${ARCH}' after config, but different from wanted '${__wanted_rootfs_arch}'"
	fi
}

function artifact_rootfs_get_default_oci_target() {
	artifact_oci_target_base="${GHCR_SOURCE}/armbian/os/"
}

function artifact_rootfs_is_available_in_local_cache() {
	is_artifact_available_in_local_cache
}

function artifact_rootfs_is_available_in_remote_cache() {
	is_artifact_available_in_remote_cache
}

function artifact_rootfs_obtain_from_remote_cache() {
	obtain_artifact_from_remote_cache
}

function artifact_rootfs_deploy_to_remote_cache() {
	upload_artifact_to_oci
}
