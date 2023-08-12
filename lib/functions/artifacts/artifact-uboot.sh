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
	artifact_input_variables[ARCH]="${ARCH}"
}

function artifact_uboot_prepare_version() {
	artifact_version="undetermined"        # outer scope
	artifact_version_reason="undetermined" # outer scope

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

	# Sanity check, the SHA1 gotta be sane.
	[[ "${GIT_INFO_UBOOT[SHA1]}" =~ ^[0-9a-f]{40}$ ]] || exit_with_error "SHA1 is not sane: '${GIT_INFO_UBOOT[SHA1]}'"

	declare short_sha1="${GIT_INFO_UBOOT[SHA1]:0:${short_hash_size}}"

	# get the uboot patches hash...
	# @TODO: why not just delegate this to the python patching, with some "dry-run" / hash-only option?
	# @TODO: this is even more grave in case of u-boot: v2022.10 has patches for many boards inside, gotta resolve.
	declare patches_hash="undetermined"
	declare hash_files="undetermined"
	declare -a uboot_patch_dirs=()
	for patch_dir in ${BOOTPATCHDIR}; do
		uboot_patch_dirs+=("${SRC}/patch/u-boot/${patch_dir}" "${USERPATCHES_PATH}/u-boot/${patch_dir}")
	done

	if [[ -n "${ATFSOURCE}" && "${ATFSOURCE}" != "none" ]]; then
		uboot_patch_dirs+=("${SRC}/patch/atf/${ATFPATCHDIR}" "${USERPATCHES_PATH}/atf/${ATFPATCHDIR}")
	fi

	if [[ -n "${CRUSTCONFIG}" ]]; then
		uboot_patch_dirs+=("${SRC}/patch/crust/${CRUSTPATCHDIR}" "${USERPATCHES_PATH}/crust/${CRUSTPATCHDIR}")
	fi

	calculate_hash_for_all_files_in_dirs "${uboot_patch_dirs[@]}"
	patches_hash="${hash_files}"
	declare uboot_patches_hash_short="${patches_hash:0:${short_hash_size}}"

	# Hash the extension hooks
	declare -a extension_hooks_to_hash=(
		"post_uboot_custom_postprocess" "fetch_custom_uboot" "build_custom_uboot"
		"pre_config_uboot_target" "post_uboot_custom_postprocess" "post_uboot_custom_postprocess"
		"post_config_uboot_target"
	)
	declare -a extension_hooks_hashed=("$(dump_extension_method_sources_functions "${extension_hooks_to_hash[@]}")")
	declare hash_hooks="undetermined"
	hash_hooks="$(echo "${extension_hooks_hashed[@]}" | sha256sum | cut -d' ' -f1)"

	# Hash the old-timey hooks
	declare hash_functions="undetermined"
	calculate_hash_for_function_bodies "write_uboot_platform" "write_uboot_platform_mtd" "setup_write_uboot_platform"
	declare hash_uboot_functions="${hash_functions}"

	# Hash those two together
	declare hash_hooks_and_functions="undetermined"
	hash_hooks_and_functions="$(echo "${hash_hooks}" "${hash_uboot_functions}" | sha256sum | cut -d' ' -f1)"
	declare hash_hooks_and_functions_short="${hash_hooks_and_functions:0:${short_hash_size}}"

	# Hash variables that affect the build and package of u-boot
	declare -a vars_to_hash=(
		"${BOOTDELAY}" "${UBOOT_DEBUGGING}" "${UBOOT_TARGET_MAP}" # general for all families
		"${BOOT_SCENARIO}" "${BOOT_SUPPORT_SPI}" "${BOOT_SOC}"    # rockchip stuff, sorry.
		"${DDR_BLOB}" "${BL31_BLOB}" "${MINILOADER_BLOB}"         # More rockchip stuff, even more sorry.
		"${ATF_COMPILE}" "${ATFBRANCH}" "${ATFPATCHDIR}"          # arm-trusted-firmware stuff
		"${CRUSTCONFIG}" "${CRUSTBRANCH}" "${CRUSTPATCHDIR}"      # crust stuff
	)
	declare hash_variables="undetermined" # will be set by calculate_hash_for_variables(), which normalizes the input
	calculate_hash_for_variables "${vars_to_hash[@]}"
	declare vars_config_hash="${hash_variables}"
	declare var_config_hash_short="${vars_config_hash:0:${short_hash_size}}"

	# get the hashes of the lib/ bash sources involved...
	declare hash_files="undetermined"
	calculate_hash_for_bash_deb_artifact "${SRC}"/lib/functions/compilation/uboot*.sh # expansion
	declare bash_hash="${hash_files}"
	declare bash_hash_short="${bash_hash:0:${short_hash_size}}"

	# outer scope
	artifact_version="${GIT_INFO_UBOOT[MAKEFILE_VERSION]}-S${short_sha1}-P${uboot_patches_hash_short}-H${hash_hooks_and_functions_short}-V${var_config_hash_short}-B${bash_hash_short}"

	declare -a reasons=(
		"version \"${GIT_INFO_UBOOT[MAKEFILE_FULL_VERSION]}\""
		"git revision \"${GIT_INFO_UBOOT[SHA1]}\""
		"patches hash \"${patches_hash}\""
		"Extension hooks hash \"${hash_hooks}\""
		"uboot functions hash \"${hash_uboot_functions}\""
		"variables hash \"${vars_config_hash}\""
		"framework bash hash \"${bash_hash}\""
	)

	artifact_deb_repo="global"
	artifact_deb_arch="${ARCH}"
	artifact_version_reason="${reasons[*]}" # outer scope
	artifact_map_packages=(["uboot"]="linux-u-boot-${BOARD}-${BRANCH}")
	artifact_name="uboot-${BOARD}-${BRANCH}"
	artifact_type="deb"

	return 0
}

function artifact_uboot_build_from_sources() {
	LOG_SECTION="fetch_and_build_host_tools" do_with_logging fetch_and_build_host_tools

	if [[ -n "${ATFSOURCE}" && "${ATFSOURCE}" != "none" ]]; then
		if [[ "${ARTIFACT_BUILD_INTERACTIVE:-"no"}" == "yes" ]]; then
			display_alert "Running ATF build in interactive mode" "log file will be incomplete" "info"
			compile_atf

			if [[ "${CREATE_PATCHES_ATF:-"no"}" == "yes" ]]; then
				return 0 # stop here, otherwise it would build u-boot below...
			fi
		else
			LOG_SECTION="compile_atf" do_with_logging compile_atf
		fi
	fi

	if [[ -n "${CRUSTCONFIG}" ]]; then
		if [[ "${ARTIFACT_BUILD_INTERACTIVE:-"no"}" == "yes" ]]; then
			display_alert "Running crust build in interactive mode" "log file will be incomplete" "info"
			compile_crust

			if [[ "${CREATE_PATCHES_CRUST:-"no"}" == "yes" ]]; then
				return 0 # stop here, otherwise it would build u-boot below...
			fi
		else
			LOG_SECTION="compile_crust" do_with_logging compile_crust
		fi
	fi

	declare uboot_git_revision="not_determined_yet"
	LOG_SECTION="uboot_prepare_git" do_with_logging_unless_user_terminal uboot_prepare_git

	# Hack, if ARTIFACT_BUILD_INTERACTIVE=yes, don't run under logging manager. Emit a warning about it.
	if [[ "${ARTIFACT_BUILD_INTERACTIVE:-"no"}" == "yes" ]]; then
		display_alert "Running uboot build in interactive mode" "log file will be incomplete" "info"
		compile_uboot
	else
		LOG_SECTION="compile_uboot" do_with_logging compile_uboot
	fi
}

function artifact_uboot_cli_adapter_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function artifact_uboot_cli_adapter_config_prep() {
	# Sanity check / cattle guard
	# If UBOOT_CONFIGURE=yes, or CREATE_PATCHES=yes, user must have used the correct CLI commands, and only add those params.
	if [[ "${UBOOT_CONFIGURE}" == "yes" && ("${ARMBIAN_COMMAND}" != "uboot-config") ]]; then
		exit_with_error "UBOOT_CONFIGURE=yes is not supported anymore. Please use the new 'uboot-config' CLI command. Current command: '${ARMBIAN_COMMAND}'"
	fi

	if [[ "${CREATE_PATCHES}" == "yes" && "${ARMBIAN_COMMAND}" != "uboot-patch" ]]; then
		exit_with_error "CREATE_PATCHES=yes is not supported anymore. Please use the new 'uboot-patch' CLI command. Current command: '${ARMBIAN_COMMAND}'"
	fi

	use_board="yes" prep_conf_main_minimal_ni < /dev/null # no stdin for this, so it bombs if tries to be interactive.
}

function artifact_uboot_get_default_oci_target() {
	artifact_oci_target_base="${GHCR_SOURCE}/armbian/os/"
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
