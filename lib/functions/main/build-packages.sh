#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

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

	### NEW / Artifact system

	# Determine which artifacts to build.
	declare -a artifacts_to_build=()
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

	display_alert "Artifacts to build:" "${artifacts_to_build[*]}" "debug"

	# For each artifact, try to obtain them from the local cache, remote cache, or build them.
	# Store info about all artifacts in the process, for later use (eg during package installation in distro-agnostic).
	declare -g -a image_artifacts_all=()
	declare -g -A image_artifacts_packages=()
	declare -g -A image_artifacts_debs=()
	declare one_artifact one_artifact_package
	for one_artifact in "${artifacts_to_build[@]}"; do
		declare -A artifact_map_packages=()
		declare -A artifact_map_debs=()

		WHAT="${one_artifact}" build_artifact_for_image

		# store info about this artifact's debs and packages
		for one_artifact_package in "${!artifact_map_packages[@]}"; do
			image_artifacts_all+=("${one_artifact_package}")
			image_artifacts_packages["${one_artifact_package}"]="${artifact_map_packages[${one_artifact_package}]}"
			image_artifacts_debs["${one_artifact_package}"]="${artifact_map_debs[${one_artifact_package}]}"
		done
	done

	debug_dict image_artifacts_packages
	debug_dict image_artifacts_debs

	### OLD / Legacy / Needs conversion to new artifact system @TODO

	# Compile armbian-config if packed .deb does not exist or use the one from repository
	if [[ ! -f ${DEB_STORAGE}/armbian-config_${REVISION}_all.deb ]]; then
		if [[ "${REPOSITORY_INSTALL}" != *armbian-config* ]]; then
			LOG_SECTION="compile_armbian-config" do_with_logging compile_armbian-config
		fi
	fi

	# Compile armbian-zsh if packed .deb does not exist or use the one from repository
	if [[ ! -f ${DEB_STORAGE}/armbian-zsh_${REVISION}_all.deb ]]; then
		if [[ "${REPOSITORY_INSTALL}" != *armbian-zsh* ]]; then
			LOG_SECTION="compile_armbian-zsh" do_with_logging compile_armbian-zsh
		fi
	fi

	# Compile plymouth-theme-armbian if packed .deb does not exist or use the one from repository
	if [[ ! -f ${DEB_STORAGE}/plymouth-theme-armbian_${REVISION}_all.deb ]]; then
		if [[ "${REPOSITORY_INSTALL}" != *plymouth-theme-armbian* ]]; then
			LOG_SECTION="compile_plymouth_theme_armbian" do_with_logging compile_plymouth_theme_armbian
		fi
	fi

	overlayfs_wrapper "cleanup"
	reset_uid_owner "${DEB_STORAGE}"

	# end of kernel-only, so display what was built.
	if [[ "${KERNEL_ONLY}" != "yes" ]]; then
		display_alert "Kernel build done" "@host" "target-reached"
		display_alert "Target directory" "${DEB_STORAGE}/" "info"
		display_alert "File name" "${CHOSEN_KERNEL}_${REVISION}_${ARCH}.deb" "info"
	elif [[ "${KERNEL_ONLY}" == "yes" ]]; then
		display_alert "using legacy option" "KERNEL_ONLY=yes; stopping build mid-packages" "warn"
		return 0
	fi

	# Further packages require aggregation (BSPs use aggregated stuff, etc)
	assert_requires_aggregation # Bombs if aggregation has not run

	# create board support package
	if [[ -n "${RELEASE}" && ! -f "${DEB_STORAGE}/${BSP_CLI_PACKAGE_FULLNAME}.deb" && "${REPOSITORY_INSTALL}" != *armbian-bsp-cli* ]]; then
		LOG_SECTION="create_board_package" do_with_logging create_board_package
	fi

	# create desktop package
	if [[ -n "${RELEASE}" && "${DESKTOP_ENVIRONMENT}" && ! -f "${DEB_STORAGE}/$RELEASE/${CHOSEN_DESKTOP}_${REVISION}_all.deb" && "${REPOSITORY_INSTALL}" != *armbian-desktop* ]]; then
		LOG_SECTION="create_desktop_package" do_with_logging create_desktop_package
	fi
	if [[ -n "${RELEASE}" && "${DESKTOP_ENVIRONMENT}" && ! -f "${DEB_STORAGE}/${RELEASE}/${BSP_DESKTOP_PACKAGE_FULLNAME}.deb" && "${REPOSITORY_INSTALL}" != *armbian-bsp-desktop* ]]; then
		LOG_SECTION="create_bsp_desktop_package" do_with_logging create_bsp_desktop_package
	fi

	# Reset owner of DEB_STORAGE, if needed. Might be a lot of packages there, but such is life.
	# @TODO: might be needed also during 'cleanup': if some package fails, the previous package might be left owned by root.
	reset_uid_owner "${DEB_STORAGE}"

	# At this point, the WORKDIR should be clean. Add debug info.
	debug_tmpfs_show_usage "AFTER ALL PKGS BUILT"
}
