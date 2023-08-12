#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# keyed by RELEASE/DESKTOP_ENVIRONMENT
# not by BOARD, nor BRANCH
# use case "metapackage for installing a minimal xfce" on any board

function compile_armbian-desktop() {
	: "${artifact_name:?artifact_name is not set}"
	: "${artifact_version:?artifact_version is not set}"
	: "${RELEASE:?RELEASE is not set}"
	: "${DISTRIBUTION:?DISTRIBUTION is not set}"
	: "${DESKTOP_ENVIRONMENT:?DESKTOP_ENVIRONMENT is not set}"
	: "${DESKTOP_ENVIRONMENT_CONFIG_NAME:?DESKTOP_ENVIRONMENT_CONFIG_NAME is not set}"

	assert_requires_aggregation # this requires aggregation to have been run
	: "${AGGREGATED_DESKTOP_POSTINST:?AGGREGATED_DESKTOP_POSTINST is not set}"
	: "${AGGREGATED_DESKTOP_CREATE_DESKTOP_PACKAGE:?AGGREGATED_DESKTOP_CREATE_DESKTOP_PACKAGE is not set}"
	: "${AGGREGATED_PACKAGES_DESKTOP_COMMA:?AGGREGATED_PACKAGES_DESKTOP_COMMA is not set}"

	# produced by aggregation.py
	display_alert "bsp-desktop: AGGREGATED_PACKAGES_DESKTOP_COMMA" "'${AGGREGATED_PACKAGES_DESKTOP_COMMA}'" "debug"
	# @TODO: AGGREGATED_PACKAGES_DESKTOP_COMMA includes appgroups, which can vary.

	display_alert "Creating common package for '${DESKTOP_ENVIRONMENT}' desktops" "${artifact_name} :: ${artifact_version}" "info"

	declare cleanup_id="" destination=""
	prepare_temp_dir_in_workdir_and_schedule_cleanup "bsp-desktop" cleanup_id destination # namerefs

	mkdir -p "${destination}"/DEBIAN
	mkdir -p "${destination}"/etc/armbian

	# set up control file
	cat <<- EOF > "${destination}"/DEBIAN/control
		Package: ${artifact_name}
		Version: ${artifact_version}
		Architecture: all
		Maintainer: $MAINTAINER <$MAINTAINERMAIL>
		Section: xorg
		Priority: optional
		Recommends: ${AGGREGATED_PACKAGES_DESKTOP_COMMA}, armbian-bsp-desktop
		Provides: armbian-${RELEASE}-desktop
		Conflicts: gdm3
		Description: Armbian desktop for ${DISTRIBUTION} ${RELEASE} ${DESKTOP_ENVIRONMENT}
	EOF

	# postinst. generated script, gathered from scripts in files in configuration. # @TODO: extensions could do this much better
	generic_artifact_package_hook_helper "postinst" "${AGGREGATED_DESKTOP_POSTINST}"

	# @TODO: error information? This is very likely to explode, and a bad implementation of extensibility.
	display_alert "Running desktop-specific aggregated prepare script" "AGGREGATED_DESKTOP_CREATE_DESKTOP_PACKAGE" "debug"
	eval "${AGGREGATED_DESKTOP_CREATE_DESKTOP_PACKAGE}"
	display_alert "Running desktop-specific aggregated prepare script" "AGGREGATED_DESKTOP_CREATE_DESKTOP_PACKAGE" "debug"

	fakeroot_dpkg_deb_build "${destination}" "armbian-desktop"

	done_with_temp_dir "${cleanup_id}" # changes cwd to "${SRC}" and fires the cleanup function early
}
