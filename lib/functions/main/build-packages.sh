#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
function determine_artifacts_to_build_for_image() {
	# outer scope: declare -a artifacts_to_build=()
	if [[ "${BOOTCONFIG}" != "none" ]]; then
		artifacts_to_build+=("uboot")
	fi
	if [[ -n $KERNELSOURCE ]]; then
		artifacts_to_build+=("kernel")
	fi

	if [[ "${INSTALL_ARMBIAN_FIRMWARE:-yes}" == "yes" ]]; then
		if [[ ${BOARD_FIRMWARE_INSTALL:-""} == "-full" ]]; then
			artifacts_to_build+=("full_firmware")
		else
			artifacts_to_build+=("firmware")
		fi
	fi

	# Userspace, RELEASE+ARCH specific, replaces the original distro's base-files
	# This is always built, but only installed if KEEP_ORIGINAL_OS_RELEASE!=yes.
	artifacts_to_build+=("armbian-base-files")

	if [[ "${DISTRIBUTION}" == "Ubuntu" ]]; then
		artifacts_to_build+=("fake_ubuntu_advantage_tools")
	fi

	if [[ "${PACKAGE_LIST_RM}" != *armbian-config* ]]; then
		if [[ $BUILD_MINIMAL != yes ]]; then
			artifacts_to_build+=("armbian-config")
		fi
	fi

	if [[ "${PACKAGE_LIST_RM}" != *armbian-zsh* ]]; then
		if [[ $BUILD_MINIMAL != yes ]]; then
			artifacts_to_build+=("armbian-zsh")
		fi
	fi

	if [[ $PLYMOUTH == yes ]]; then
		artifacts_to_build+=("armbian-plymouth-theme")
	fi

	# Userspace, BOARD+BRANCH specific (not RELEASE)
	artifacts_to_build+=("armbian-bsp-cli")

	# Userspace, RELEASE-specific artifacts.
	if [[ -n "${RELEASE}" ]]; then
		if [[ -n "${DESKTOP_ENVIRONMENT}" ]]; then
			artifacts_to_build+=("armbian-desktop")
			artifacts_to_build+=("armbian-bsp-desktop")
		fi
	fi

	# If we're only dumping the config, include the rootfs artifact.
	# In a "real" build, this artifact is built/consumed by get_or_create_rootfs_cache_chroot_sdcard(), not here.
	if [[ "${CONFIG_DEFS_ONLY}" == "yes" ]]; then
		artifacts_to_build+=("rootfs")
	fi

}

function main_default_build_packages() {
	# early cleaning for sources, since fetch_and_build_host_tools() uses it.
	if [[ "${CLEAN_LEVEL}" == *sources* ]]; then
		LOG_SECTION="cleaning_early_sources" do_with_logging general_cleaning "sources"
	fi

	# ignore updates help on building all images - for internal purposes
	if [[ "${IGNORE_UPDATES}" != "yes" ]]; then
		LOG_SECTION="clean_deprecated_mountpoints" do_with_logging clean_deprecated_mountpoints

		for cleaning_fragment in $(tr ',' ' ' <<< "${CLEAN_LEVEL}"); do
			if [[ $cleaning_fragment != sources ]] && [[ $cleaning_fragment != none ]] && [[ $cleaning_fragment != make* ]]; then
				LOG_SECTION="cleaning_${cleaning_fragment}" do_with_logging general_cleaning "${cleaning_fragment}"
			fi
		done
	fi

	# determine which artifacts to build.
	declare -a artifacts_to_build=()
	determine_artifacts_to_build_for_image
	display_alert "Artifacts to build:" "${artifacts_to_build[*]}" "debug"

	# For each artifact, try to obtain them from the local cache, remote cache, or build them.
	# Store info about all artifacts in the process, for later use (eg during package installation in distro-agnostic).
	declare -g -a image_artifacts_all=()
	declare -g -A image_artifacts_packages=()
	declare -g -A image_artifacts_packages_version=()
	declare -g -A image_artifacts_packages_version_reversioned=()
	declare -g -A image_artifacts_debs=()
	declare -g -A image_artifacts_debs_reversioned=()
	declare -A -g image_artifacts_debs_installed=()

	declare one_artifact one_artifact_package
	for one_artifact in "${artifacts_to_build[@]}"; do
		declare -A artifact_map_packages=()
		declare -A artifact_map_debs=()
		declare -A artifact_map_debs_reversioned=()
		declare artifact_version

		WHAT="${one_artifact}" build_artifact_for_image

		# store info about this artifact's debs and packages
		for one_artifact_package in "${!artifact_map_packages[@]}"; do
			image_artifacts_all+=("${one_artifact_package}")
			image_artifacts_packages["${one_artifact_package}"]="${artifact_map_packages[${one_artifact_package}]}"
			image_artifacts_debs["${one_artifact_package}"]="${artifact_map_debs[${one_artifact_package}]}"
			image_artifacts_debs_reversioned["${one_artifact_package}"]="${artifact_map_debs_reversioned[${one_artifact_package}]}"
			image_artifacts_packages_version["${artifact_map_packages[${one_artifact_package}]}"]="${artifact_version}"
			image_artifacts_packages_version_reversioned["${artifact_map_packages[${one_artifact_package}]}"]="${artifact_final_version_reversioned}"
			image_artifacts_debs_installed["${one_artifact_package}"]="no" # initialize, install_artifact_deb_chroot() will set to "yes" when installed.
		done
	done

	debug_dict image_artifacts_packages
	debug_dict image_artifacts_debs
	debug_dict image_artifacts_packages_version
	debug_dict image_artifacts_debs_installed

	overlayfs_wrapper "cleanup"
	reset_uid_owner "${DEB_STORAGE}"

	# At this point, the WORKDIR should be clean. Add debug info.
	debug_tmpfs_show_usage "AFTER ALL PKGS BUILT"
}
