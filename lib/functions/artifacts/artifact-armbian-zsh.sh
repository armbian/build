#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function artifact_armbian-zsh_config_dump() {
	# artifact_input_variables: None, for armbian-zsh.
	:
}

function artifact_armbian-zsh_prepare_version() {
	artifact_version="undetermined"        # outer scope
	artifact_version_reason="undetermined" # outer scope

	local ARMBIAN_ZSH_SOURCE="${ARMBIAN_ZSH_SOURCE:-"https://github.com/ohmyzsh/ohmyzsh"}"
	local ARMBIAN_ZSH_BRANCH="branch:${ARMBIAN_ZSH_BRANCH:-"master"}"

	debug_var ARMBIAN_ZSH_SOURCE
	debug_var ARMBIAN_ZSH_BRANCH

	declare short_hash_size=4

	declare -A GIT_INFO_ARMBIAN_ZSH=([GIT_SOURCE]="${ARMBIAN_ZSH_SOURCE}" [GIT_REF]="${ARMBIAN_ZSH_BRANCH}")
	run_memoized GIT_INFO_ARMBIAN_ZSH "git2info" memoized_git_ref_to_info
	debug_dict GIT_INFO_ARMBIAN_ZSH

	# Sanity check, the SHA1 gotta be sane.
	[[ "${GIT_INFO_ARMBIAN_ZSH[SHA1]}" =~ ^[0-9a-f]{40}$ ]] || exit_with_error "SHA1 is not sane: '${GIT_INFO_ARMBIAN_ZSH[SHA1]}'"

	declare fake_unchanging_base_version="1"

	declare short_sha1="${GIT_INFO_ARMBIAN_ZSH[SHA1]:0:${short_hash_size}}"

	# get the hashes of the lib/ bash sources involved...
	declare hash_files="undetermined"
	calculate_hash_for_files "${SRC}"/lib/functions/compilation/packages/armbian-zsh-deb.sh
	declare bash_hash="${hash_files}"
	declare bash_hash_short="${bash_hash:0:${short_hash_size}}"

	# outer scope
	artifact_version="${artifact_prefix_version}${fake_unchanging_base_version}-SA${short_sha1}-B${bash_hash_short}"

	declare -a reasons=(
		"Armbian armbian-zsh git revision \"${GIT_INFO_ARMBIAN_ZSH[SHA1]}\""
		"framework bash hash \"${bash_hash}\""
	)

	artifact_version_reason="${reasons[*]}" # outer scope

	artifact_map_packages=(
		["armbian-zsh"]="armbian-zsh"
	)

	artifact_map_debs=(
		["armbian-zsh"]="armbian-zsh_${artifact_version}_all.deb"
	)

	artifact_name="armbian-zsh"
	artifact_type="deb"
	artifact_base_dir="${DEB_STORAGE}"
	artifact_final_file="${DEB_STORAGE}/armbian-zsh_${artifact_version}_all.deb"

	return 0
}

function artifact_armbian-zsh_build_from_sources() {
	LOG_SECTION="compile_armbian-zsh" do_with_logging compile_armbian-zsh
}

function artifact_armbian-zsh_cli_adapter_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function artifact_armbian-zsh_cli_adapter_config_prep() {
	use_board="no" prep_conf_main_minimal_ni < /dev/null # no stdin for this, so it bombs if tries to be interactive.
}

function artifact_armbian-zsh_get_default_oci_target() {
	artifact_oci_target_base="${GHCR_SOURCE}/armbian/cache-packages/"
}

function artifact_armbian-zsh_is_available_in_local_cache() {
	is_artifact_available_in_local_cache
}

function artifact_armbian-zsh_is_available_in_remote_cache() {
	is_artifact_available_in_remote_cache
}

function artifact_armbian-zsh_obtain_from_remote_cache() {
	obtain_artifact_from_remote_cache
}

function artifact_armbian-zsh_deploy_to_remote_cache() {
	upload_artifact_to_oci
}
