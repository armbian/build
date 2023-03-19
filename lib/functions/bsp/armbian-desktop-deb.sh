#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function compile_armbian-desktop() {
	: "${artifact_version:?artifact_version is not set}"

	# produced by aggregation.py
	display_alert "bsp-desktop: AGGREGATED_PACKAGES_DESKTOP_COMMA" "'${AGGREGATED_PACKAGES_DESKTOP_COMMA}'" "debug"

	declare cleanup_id="" tmp_dir=""
	prepare_temp_dir_in_workdir_and_schedule_cleanup "bsp-desktop" cleanup_id tmp_dir # namerefs

	declare destination="${tmp_dir}/${BOARD}/${CHOSEN_DESKTOP}_${artifact_version}_all"
	rm -rf "${destination}"
	mkdir -p "${destination}"/DEBIAN

	# set up control file
	cat <<- EOF > "${destination}"/DEBIAN/control
		Package: ${CHOSEN_DESKTOP}
		Version: ${artifact_version}
		Architecture: all
		Maintainer: $MAINTAINER <$MAINTAINERMAIL>
		Installed-Size: 1
		Section: xorg
		Priority: optional
		Recommends: ${AGGREGATED_PACKAGES_DESKTOP_COMMA}, armbian-bsp-desktop
		Provides: ${CHOSEN_DESKTOP}, armbian-${RELEASE}-desktop
		Conflicts: gdm3
		Description: Armbian desktop for ${DISTRIBUTION} ${RELEASE}
	EOF

	# Recreating the DEBIAN/postinst file
	echo "#!/bin/bash -e" > "${destination}/DEBIAN/postinst"
	echo "${AGGREGATED_DESKTOP_POSTINST}" >> "${destination}/DEBIAN/postinst"
	echo "exit 0" >> "${destination}/DEBIAN/postinst"
	chmod 755 "${destination}"/DEBIAN/postinst

	# Armbian create_desktop_package scripts
	mkdir -p "${destination}"/etc/armbian
	# @TODO: error information? This is very likely to explode....
	eval "${AGGREGATED_DESKTOP_CREATE_DESKTOP_PACKAGE}"

	display_alert "Building desktop package" "${CHOSEN_DESKTOP}_${artifact_version}_all" "info"

	mkdir -p "${DEB_STORAGE}/${RELEASE}"
	#cd "${destination}" || exit_with_error "Failed to cd to ${destination}"
	#cd ..
	fakeroot_dpkg_deb_build "${destination}" "${DEB_STORAGE}/${RELEASE}"

	done_with_temp_dir "${cleanup_id}" # changes cwd to "${SRC}" and fires the cleanup function early
}
