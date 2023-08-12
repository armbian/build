#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# bsp-desktop should be like bsp-cli
# it is keyed by RELEASE/BOARD/BRANCH, thus "a common package for all desktops with the same board/branch in a given release"
# # @TODO: it should NOT be dependendent on a specific (xfce/mate/etc) desktop environment
#          but right now it is, since aggregation depends on it, and needs further changes @TODO: we should split.
# main use case to include vendor wallpaper, etc

function compile_armbian-bsp-desktop() {
	: "${artifact_name:?artifact_name is not set}"
	: "${artifact_version:?artifact_version is not set}"
	: "${RELEASE:?RELEASE is not set}"
	: "${BOARD:?BOARD is not set}"
	: "${BRANCH:?BRANCH is not set}"
	: "${DISTRIBUTION:?DISTRIBUTION is not set}"

	: "${DESKTOP_ENVIRONMENT:?DESKTOP_ENVIRONMENT is not set}"
	: "${DESKTOP_ENVIRONMENT_CONFIG_NAME:?DESKTOP_ENVIRONMENT_CONFIG_NAME is not set}"

	assert_requires_aggregation # this requires aggregation to have been run
	: "${AGGREGATED_DESKTOP_BSP_PREPARE:?AGGREGATED_DESKTOP_BSP_PREPARE is not set}"
	: "${AGGREGATED_DESKTOP_BSP_POSTINST:?AGGREGATED_DESKTOP_BSP_POSTINST is not set}"

	# @TODO: this is not true, as you can see; this is specific per-desktop due to aggregation
	display_alert "Creating bsp-desktop for release '${RELEASE}' common to all desktops on board '${BOARD}' branch '${BRANCH}'" "${artifact_name} :: ${artifact_version}" "info"

	declare cleanup_id="" destination=""
	prepare_temp_dir_in_workdir_and_schedule_cleanup "bsp-desktop" cleanup_id destination # namerefs

	mkdir -p "${destination}"/etc/armbian
	mkdir -p "${destination}"/DEBIAN

	copy_all_packages_files_for "bsp-desktop"

	# set up control file
	cat <<- EOF > "${destination}"/DEBIAN/control
		Package: ${artifact_name}
		Version: ${artifact_version}
		Architecture: $ARCH
		Maintainer: $MAINTAINER <$MAINTAINERMAIL>
		Section: xorg
		Priority: optional
		Provides: armbian-bsp-desktop, armbian-bsp-desktop-${BOARD}
		Description: Armbian bsp-desktop for release ${RELEASE}, common for all desktop environments on ${ARCH} ${BOARD} machines on ${BRANCH} branch
	EOF

	# postinst. generated script, gathered from scripts in files in configuration. # @TODO: extensions could do this much better
	generic_artifact_package_hook_helper "postinst" "${AGGREGATED_DESKTOP_BSP_POSTINST}"

	# @TODO: error information? This is very likely to explode, and a bad implementation of extensibility.
	display_alert "Running bsp-desktop -specific aggregated prepare script" "AGGREGATED_DESKTOP_BSP_PREPARE" "debug"
	eval "${AGGREGATED_DESKTOP_BSP_PREPARE}"
	display_alert "Done with bsp-desktop -specific aggregated prepare script" "AGGREGATED_DESKTOP_BSP_PREPARE" "debug"

	fakeroot_dpkg_deb_build "${destination}" "armbian-bsp-desktop"

	done_with_temp_dir "${cleanup_id}" # changes cwd to "${SRC}" and fires the cleanup function early
}
