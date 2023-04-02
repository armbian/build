#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function artifact_uboot_config_dump() {
	artifact_input_variables[BOOTSOURCE]="${BOOTSOURCE}"
	artifact_input_variables[BOOTBRANCH]="${BOOTBRANCH}"
	artifact_input_variables[BOOTPATCHDIR]="${BOOTPATCHDIR}"
	artifact_input_variables[BOARD]="${BOARD}"
	artifact_input_variables[BRANCH]="${BRANCH}"
}

function artifact_uboot_prepare_version() {
	artifact_version="undetermined"        # outer scope
	artifact_version_reason="undetermined" # outer scope
	[[ -z "${artifact_prefix_version}" ]] && exit_with_error "artifact_prefix_version is not set"

	# Prepare the version, "sans-repos": just the armbian/build repo contents are available.
	# It is OK to reach out to the internet for a curl or ls-remote, but not for a git clone/fetch.

	# - Given BOOTSOURCE and BOOTBRANCH, get:
	#    - SHA1 of the commit (this is generic... and used for other pkgs)
	#    - The first 10 lines of the root Makefile at that commit (cached lookup, same SHA1=same Makefile)
	#      - This gives us the full version plus codename.
	# - Get the u-boot patches hash. (could just hash the BOOTPATCHDIR non-disabled contents, or use Python patching proper?)
	# - Hash of the relevant lib/ bash sources involved, say compilation/uboot*.sh etc
	# All those produce a version string like:
	# 2023.11-<4-digit-SHA1>_<4_digit_patches>

	debug_var BOOTSOURCE
	debug_var BOOTBRANCH
	debug_var BOOTPATCHDIR
	debug_var BOARD
	debug_var BRANCH

	declare short_hash_size=4

	declare -A GIT_INFO_UBOOT=([GIT_SOURCE]="${BOOTSOURCE}" [GIT_REF]="${BOOTBRANCH}")
	run_memoized GIT_INFO_UBOOT "git2info" memoized_git_ref_to_info "include_makefile_body"
	debug_dict GIT_INFO_UBOOT

	declare short_sha1="${GIT_INFO_UBOOT[SHA1]:0:${short_hash_size}}"

	# get the uboot patches hash...
	# @TODO: why not just delegate this to the python patching, with some "dry-run" / hash-only option?
	# @TODO: this is even more grave in case of u-boot: v2022.10 has patches for many boards inside, gotta resolve.
	declare patches_hash="undetermined"
	declare hash_files="undetermined"
	calculate_hash_for_all_files_in_dirs "${SRC}/patch/u-boot/${BOOTPATCHDIR}" "${USERPATCHES_PATH}/u-boot/${BOOTPATCHDIR}"
	patches_hash="${hash_files}"
	declare uboot_patches_hash_short="${patches_hash:0:${short_hash_size}}"

	# get the hashes of the lib/ bash sources involved...
	declare hash_files="undetermined"
	calculate_hash_for_files "${SRC}"/lib/functions/compilation/uboot*.sh
	declare bash_hash="${hash_files}"
	declare bash_hash_short="${bash_hash:0:${short_hash_size}}"

	# outer scope
	artifact_version="${artifact_prefix_version}${GIT_INFO_UBOOT[MAKEFILE_VERSION]}-S${short_sha1}-P${uboot_patches_hash_short}-B${bash_hash_short}"

	declare -a reasons=(
		"version \"${GIT_INFO_UBOOT[MAKEFILE_FULL_VERSION]}\""
		"git revision \"${GIT_INFO_UBOOT[SHA1]}\""
		"patches hash \"${patches_hash}\""
		"framework bash hash \"${bash_hash}\""
	)

	artifact_version_reason="${reasons[*]}" # outer scope

	artifact_map_packages=(
		["uboot"]="linux-u-boot-${BOARD}-${BRANCH}"
	)

	artifact_map_debs=(
		["uboot"]="linux-u-boot-${BOARD}-${BRANCH}_${artifact_version}_${ARCH}.deb"
	)

	artifact_name="uboot-${BOARD}-${BRANCH}"
	artifact_type="deb"
	artifact_base_dir="${DEB_STORAGE}"
	artifact_final_file="${DEB_STORAGE}/linux-u-boot-${BOARD}-${BRANCH}_${artifact_version}_${ARCH}.deb"

	return 0
}

function artifact_uboot_build_from_sources() {
	LOG_SECTION="fetch_and_build_host_tools" do_with_logging fetch_and_build_host_tools

	if [[ -n "${ATFSOURCE}" && "${ATFSOURCE}" != "none" ]]; then
		LOG_SECTION="compile_atf" do_with_logging compile_atf
	fi

	declare uboot_git_revision="not_determined_yet"
	LOG_SECTION="uboot_prepare_git" do_with_logging_unless_user_terminal uboot_prepare_git
	LOG_SECTION="compile_uboot" do_with_logging compile_uboot
}

function artifact_uboot_cli_adapter_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function artifact_uboot_cli_adapter_config_prep() {
	use_board="yes" prep_conf_main_minimal_ni < /dev/null # no stdin for this, so it bombs if tries to be interactive.
}

function artifact_uboot_get_default_oci_target() {
	artifact_oci_target_base="ghcr.io/armbian/cache-uboot/"
}

function artifact_uboot_is_available_in_local_cache() {
	is_artifact_available_in_local_cache
}

function artifact_uboot_is_available_in_remote_cache() {
	is_artifact_available_in_remote_cache
}

function artifact_uboot_obtain_from_remote_cache() {
	obtain_artifact_from_remote_cache
}

function artifact_uboot_deploy_to_remote_cache() {
	upload_artifact_to_oci
}
