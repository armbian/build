#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# This is run in a logging section.
# Prepare the version, "sans-repos": just the armbian/build repo contents are available.
# It is OK to reach out to the internet for a curl or ls-remote, but not for a git clone, but
# you *must* _cache_ results on disk @TODO with a TTL determined by live code, not preset in cached entries.
function artifact_kernel_prepare_version() {
	artifact_version="undetermined"        # outer scope
	artifact_version_reason="undetermined" # outer scope
	[[ -z "${artifact_prefix_version}" ]] && exit_with_error "artifact_prefix_version is not set"

	# - Given KERNELSOURCE and KERNELBRANCH, get:
	#    - SHA1 of the commit (this is generic... and used for other pkgs)
	#    - (unless KERNEL_SKIP_MAKEFILE_VERSION=yes) The first 10 lines of the root Makefile at that commit
	#         (cached lookup, same SHA1=same Makefile, http GET, not cloned)
	#      - This gives us the full version plus codename, plus catches "version shenanigans" possibly done by patches...
	#    - @TODO: Make sure this is sane, ref KERNEL_MAJOR_MINOR; it's transitional, but we need to be sure it's sane.
	# - Get the drivers patch hash (given LINUXFAMILY and the vX.Z.Y version) - the harness can do this by hashing patches and bash code
	# - Get the kernel patches hash. (@TODO currently hashing files directly, use Python patching proper)
	# - Get the kernel .config hash, composed of
	#    - KERNELCONFIG .config hash (contents); except if KERNEL_CONFIGURE=yes, then force "999999" (six-nines)
	#    - extensions mechanism, each hook has an array of hashes that is then hashed together; see the hooks docs.
	# - Hash of the relevant lib/ bash sources involved, say compilation/kernel*.sh etc
	# All those produce a version string like:
	# 6.2-rc7-S4ec5-D1c5d-P0000-Ca00bHc1f3-B6d7b

	# - This code first calculates the globally uniquely-identifying version string for, and then builds, exactly one (01, um,
	#   uno, ein) kernel.
	#   - This produces exacly one "linux-image" .deb package, and  _might_ also produce "linux-dtb" and "linux-headers"
	#     packages.
	#   - All the .debs have the same version string, which is included in the "Version:" field of the .deb control file.
	# - "Version: " has special significance in Debian repo mgmt: it governs how "apt upgrade" decides what to upgrade to.
	# - Note!! how BOARD is not an input here. It is required though by the configuration step;
	#   - BOARDs can have hooks that completely change  the kernel, including creating new LINUXFAMILY's 🫠
	#   - It is assumed the process to obtain "all kernels to build"  involves
	#     - a loop over all boards, and then a loop over all all the  BOARD's KERNEL_TARGET's,
	#     - map: obtain all the *effective  configurations* after all hooks are run
	#     - reduce:  to "${LINUXFAMILY}-${BRANCH}", but keep an "example" BOARD= for each group, so that it can be input to
	#       this building process 🤯
	# - Also note: BOARDFAMILY is not an input here; and merely a mechanism for BOARDs to share some common defs.
	#     - That was later (but pre-armbian-next) made more complicated by sourcing, "families/includes/<xxx>_common.inc"
	# - 👉 tl;dr: Armbian kernels can't have per-board patches or configs; "family code" is a lie; repo management is hell.
	debug_var BOARD              # Heh.
	debug_var BOARDFAMILY        # Heh.
	debug_var KERNEL_MAJOR_MINOR # Double heh. transitional stuff, from when armbian-next began. 🤣
	debug_var BRANCH
	debug_var REVISION
	debug_var KERNELSOURCE
	debug_var KERNELBRANCH
	debug_var LINUXFAMILY
	debug_var KERNELPATCHDIR
	debug_var KERNEL_SKIP_MAKEFILE_VERSION
	debug_var KERNEL_CONFIGURE

	declare short_hash_size=4

	declare -A GIT_INFO_KERNEL=([GIT_SOURCE]="${KERNELSOURCE}" [GIT_REF]="${KERNELBRANCH}")

	if [[ "${KERNEL_SKIP_MAKEFILE_VERSION:-"no"}" == "yes" ]]; then
		display_alert "Skipping Makefile version for kernel" "due to KERNEL_SKIP_MAKEFILE_VERSION=yes" "info"
		run_memoized GIT_INFO_KERNEL "git2info" memoized_git_ref_to_info
	else
		run_memoized GIT_INFO_KERNEL "git2info" memoized_git_ref_to_info "include_makefile_body"
	fi
	debug_dict GIT_INFO_KERNEL

	declare short_sha1="${GIT_INFO_KERNEL[SHA1]:0:${short_hash_size}}"

	# get the drivers hash...
	declare kernel_drivers_patch_hash
	do_with_hooks kernel_drivers_create_patches_hash_only
	declare kernel_drivers_hash_short="${kernel_drivers_patch_hash:0:${short_hash_size}}"

	# get the kernel patches hash...
	# @TODO: why not just delegate this to the python patching, with some "dry-run" / hash-only option?
	declare patches_hash="undetermined"
	declare hash_files="undetermined"
	calculate_hash_for_all_files_in_dirs "${SRC}/patch/kernel/${KERNELPATCHDIR}" "${USERPATCHES_PATH}/kernel/${KERNELPATCHDIR}"
	patches_hash="${hash_files}"
	declare kernel_patches_hash_short="${patches_hash:0:${short_hash_size}}"

	# get the .config hash... also userpatches...
	declare kernel_config_source_filename="" # which actual .config was used?
	prepare_kernel_config_core_or_userpatches
	declare hash_files="undetermined"
	calculate_hash_for_files "${kernel_config_source_filename}"
	config_hash="${hash_files}"
	declare config_hash_short="${config_hash:0:${short_hash_size}}"

	# detour: if KERNEL_CONFIGURE=yes, then force "999999" (six-nines)
	if [[ "${KERNEL_CONFIGURE}" == "yes" ]]; then
		display_alert "Forcing kernel config hash to 999999" "due to KERNEL_CONFIGURE=yes" "info"
		config_hash="999999 (KERNEL_CONFIGURE=yes, unable to hash)"
		config_hash_short="999999"
	fi

	# run the extensions. they _must_ behave, and not try to modify the .config, instead just fill kernel_config_modifying_hashes
	declare kernel_config_modifying_hashes_hash="undetermined"
	declare -a kernel_config_modifying_hashes=()
	call_extensions_kernel_config
	kernel_config_modification_hash="$(echo "${kernel_config_modifying_hashes[@]}" | sha256sum | cut -d' ' -f1)"
	kernel_config_modification_hash="${kernel_config_modification_hash:0:16}" # "long hash"
	declare kernel_config_modification_hash_short="${kernel_config_modification_hash:0:${short_hash_size}}"

	# @TODO: include the compiler version? host release?

	# get the hashes of the lib/ bash sources involved...
	declare hash_files="undetermined"
	calculate_hash_for_files "${SRC}"/lib/functions/compilation/kernel*.sh
	declare bash_hash="${hash_files}"
	declare bash_hash_short="${bash_hash:0:${short_hash_size}}"

	declare common_version_suffix="S${short_sha1}-D${kernel_drivers_hash_short}-P${kernel_patches_hash_short}-C${config_hash_short}H${kernel_config_modification_hash_short}-B${bash_hash_short}"

	# outer scope
	if [[ "${KERNEL_SKIP_MAKEFILE_VERSION:-"no"}" == "yes" ]]; then
		artifact_version="${artifact_prefix_version}${common_version_suffix}"
	else
		artifact_version="${artifact_prefix_version}${GIT_INFO_KERNEL[MAKEFILE_VERSION]}-${common_version_suffix}"
	fi

	declare -a reasons=(
		"version \"${GIT_INFO_KERNEL[MAKEFILE_FULL_VERSION]}\""
		"git revision \"${GIT_INFO_KERNEL[SHA1]}\""
		"codename \"${GIT_INFO_KERNEL[MAKEFILE_CODENAME]}\""
		"drivers hash \"${kernel_drivers_patch_hash}\""
		"patches hash \"${patches_hash}\""
		".config hash \"${config_hash}\""
		".config hook hash \"${kernel_config_modification_hash}\""
		"framework bash hash \"${bash_hash}\""
	)

	artifact_version_reason="${reasons[*]}" # outer scope

	# map what "compile_kernel()" will produce - legacy deb names and versions

	# linux-image is always produced...
	artifact_map_packages=(["linux-image"]="linux-image-${BRANCH}-${LINUXFAMILY}")
	artifact_map_debs=(["linux-image"]="linux-image-${BRANCH}-${LINUXFAMILY}_${artifact_version}_${ARCH}.deb")

	# some/most kernels have also working headers...
	if [[ "${KERNEL_HAS_WORKING_HEADERS:-"no"}" == "yes" ]]; then
		artifact_map_packages+=(["linux-headers"]="linux-headers-${BRANCH}-${LINUXFAMILY}")
		artifact_map_debs+=(["linux-headers"]="linux-headers-${BRANCH}-${LINUXFAMILY}_${artifact_version}_${ARCH}.deb")
	fi

	# x86, specially, does not have working dtbs...
	if [[ "${KERNEL_BUILD_DTBS:-"yes"}" == "yes" ]]; then
		artifact_map_packages+=(["linux-dtb"]="linux-dtb-${BRANCH}-${LINUXFAMILY}")
		artifact_map_debs+=(["linux-dtb"]="linux-dtb-${BRANCH}-${LINUXFAMILY}_${artifact_version}_${ARCH}.deb")
	fi

	artifact_name="kernel-${LINUXFAMILY}-${BRANCH}"
	artifact_type="deb-tar" # this triggers processing of .deb files in the maps to produce a tarball
	artifact_base_dir="${DEB_STORAGE}"
	artifact_final_file="${DEB_STORAGE}/kernel-${LINUXFAMILY}-${BRANCH}_${artifact_version}.tar"

	return 0
}

function artifact_kernel_build_from_sources() {
	compile_kernel
	display_alert "Kernel build finished" "${artifact_version_reason}" "info"
}

function artifact_kernel_cli_adapter_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function artifact_kernel_cli_adapter_config_prep() {
	use_board="yes" prep_conf_main_minimal_ni < /dev/null # no stdin for this, so it bombs if tries to be interactive.
}

function artifact_kernel_get_default_oci_target() {
	artifact_oci_target_base="ghcr.io/armbian/cache-kernel/"
}

function artifact_kernel_is_available_in_local_cache() {
	is_artifact_available_in_local_cache
}

function artifact_kernel_is_available_in_remote_cache() {
	is_artifact_available_in_remote_cache
}

function artifact_kernel_obtain_from_remote_cache() {
	obtain_artifact_from_remote_cache
}

function artifact_kernel_deploy_to_remote_cache() {
	upload_artifact_to_oci
}
