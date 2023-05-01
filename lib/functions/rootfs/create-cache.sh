#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# called by artifact-rootfs::artifact_rootfs_prepare_version()
function calculate_rootfs_cache_id() {
	# Validate that AGGREGATED_ROOTFS_HASH is set
	[[ -z "${AGGREGATED_ROOTFS_HASH}" ]] && exit_with_error "AGGREGATED_ROOTFS_HASH is not set at calculate_rootfs_cache_id()"

	# If the vars are already set and not empty, exit_with_error
	[[ "x${packages_hash}x" != "xx" ]] && exit_with_error "packages_hash is already set"
	[[ "x${cache_type}x" != "xx" ]] && exit_with_error "cache_type is already set"

	# get the hashes of the lib/ bash sources involved...
	declare hash_files="undetermined"
	calculate_hash_for_files "${SRC}"/lib/functions/rootfs/create-cache.sh "${SRC}"/lib/functions/rootfs/rootfs-create.sh
	declare bash_hash="${hash_files}"
	declare bash_hash_short="${bash_hash:0:6}"

	# AGGREGATED_ROOTFS_HASH is produced by aggregation.py
	# Don't use a dash here, dashes are significant to legacy rootfs cache id's
	declare -g -r packages_hash="${AGGREGATED_ROOTFS_HASH:0:12}B${bash_hash_short}"

	declare cache_type="cli"
	[[ ${BUILD_DESKTOP} == yes ]] && cache_type="xfce-desktop"
	[[ -n ${DESKTOP_ENVIRONMENT} ]] && cache_type="${DESKTOP_ENVIRONMENT}-desktop"
	[[ ${BUILD_MINIMAL} == yes ]] && cache_type="minimal"

	# allow extensions to modify cache_type, since they may have used add_packages_to_rootfs() or remove_packages()
	cache_type="${cache_type}${EXTRA_ROOTFS_NAME:-""}"

	declare -g -r cache_type="${cache_type}"

	declare -g -r rootfs_cache_id="${packages_hash}"

	display_alert "calculate_rootfs_cache_id: done." "cache_type: '${cache_type}' - rootfs_cache_id: '${rootfs_cache_id}'" "debug"
}

# called by artifact-rootfs::artifact_rootfs_build_from_sources()
function create_new_rootfs_cache() {
	: "${artifact_final_file:?artifact_final_file is not set}"
	: "${artifact_final_file_basename:?artifact_final_file_basename is not set}"

	[[ ! -d "${SDCARD:?}" ]] && exit_with_error "create_new_rootfs_cache: ${SDCARD} is not a directory"
	# validate cache_type is set
	[[ -n "${cache_type}" ]] || exit_with_error "create_new_rootfs_cache: cache_type is not set"
	# validate packages_hash is set
	[[ -n "${packages_hash}" ]] || exit_with_error "create_new_rootfs_cache: packages_hash is not set"

	# compatibility with legacy code...
	declare -g cache_name="${artifact_final_file_basename}"
	declare -g cache_fname=${artifact_final_file}

	display_alert "Creating new rootfs cache" "'${cache_name}'" "info"

	create_new_rootfs_cache_via_debootstrap # in rootfs-create.sh
	create_new_rootfs_cache_tarball         # in rootfs-create.sh

	return 0 # protect against possible future short-circuiting above this
}

# this builds/gets cached rootfs artifact, extracts it to "${SDCARD}"
function get_or_create_rootfs_cache_chroot_sdcard() {
	if [[ "${ROOT_FS_CREATE_ONLY}" == yes ]]; then
		exit_with_error "Using deprecated ROOT_FS_CREATE_ONLY=yes, that is not longer supported. use 'rootfs' CLI command."
	fi

	# build the rootfs artifact; capture the filename...
	declare -g artifact_final_file artifact_version artifact_final_file artifact_file_relative
	WHAT="rootfs" build_artifact_for_image # has its own logging sections, for now
	declare -g cache_fname="${artifact_final_file}"

	# Setup the cleanup handler, possibly "again", since the artifact already set it up and consumed it, if cache missed.
	LOG_SECTION="prepare_rootfs_build_params_and_trap" do_with_logging prepare_rootfs_build_params_and_trap

	LOG_SECTION="extract_rootfs_artifact" do_with_logging extract_rootfs_artifact
	return 0
}

function extract_rootfs_artifact() {
	: "${artifact_file_relative:?artifact_file_relative is not set}"
	: "${artifact_final_file:?artifact_final_file is not set}"
	# compatibility with legacy code...
	declare cache_name="${artifact_file_relative}"
	declare cache_fname=${artifact_final_file}

	if [[ ! -f "${cache_fname}" ]]; then
		exit_with_error "get_or_create_rootfs_cache_chroot_sdcard: extract: ${cache_fname} is not a file"
	fi

	# validate sanity
	[[ "x${SDCARD}x" == "xx" ]] && exit_with_error "get_or_create_rootfs_cache_chroot_sdcard: extract: SDCARD: ${SDCARD} is not set"
	[[ ! -d "${SDCARD}" ]] && exit_with_error "get_or_create_rootfs_cache_chroot_sdcard: ${SDCARD} is not a directory"

	# @TODO: validate SDCARD is empty; if not, the artifact build "leaked" a cleanup

	local date_diff=$((($(date +%s) - $(stat -c %Y "${cache_fname}")) / 86400))
	display_alert "Extracting ${artifact_version}" "${date_diff} days old" "info"
	pv -p -b -r -c -N "$(logging_echo_prefix_for_pv "extract_rootfs") ${artifact_version}" "${cache_fname}" | zstdmt -dc | tar xp --xattrs -C "${SDCARD}"/

	declare -a pv_tar_zstdmt_pipe_status=("${PIPESTATUS[@]}") # capture and the pipe_status array from PIPESTATUS
	declare one_pipe_status
	for one_pipe_status in "${pv_tar_zstdmt_pipe_status[@]}"; do
		if [[ "$one_pipe_status" != "0" ]]; then
			exit_with_error "get_or_create_rootfs_cache_chroot_sdcard: extract: ${cache_fname} failed (${pv_tar_zstdmt_pipe_status[*]}) - corrupt cache?"
		fi
	done

	wait_for_disk_sync "after restoring rootfs cache"

	run_host_command_logged rm -v "${SDCARD}"/etc/resolv.conf
	run_host_command_logged echo "nameserver ${NAMESERVER}" ">" "${SDCARD}"/etc/resolv.conf

	create_sources_list "${RELEASE}" "${SDCARD}/"

	return 0
}
