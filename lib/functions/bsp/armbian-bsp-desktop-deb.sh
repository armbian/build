#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function compile_armbian-bsp-desktop() {
	: "${artifact_version:?artifact_version is not set}"

	display_alert "Creating board support package for desktop" "${package_name}" "info"

	local package_name="${BSP_DESKTOP_PACKAGE_FULLNAME}"
	declare cleanup_id="" tmp_dir=""
	prepare_temp_dir_in_workdir_and_schedule_cleanup "bsp-desktop2" cleanup_id tmp_dir # namerefs

	local destination=${tmp_dir}/${BOARD}/${BSP_DESKTOP_PACKAGE_FULLNAME}
	rm -rf "${destination}"
	mkdir -p "${destination}"/DEBIAN

	copy_all_packages_files_for "bsp-desktop"

	# set up control file
	cat <<- EOF > "${destination}"/DEBIAN/control
		Package: armbian-bsp-desktop-${BOARD}
		Version: ${artifact_version}
		Architecture: $ARCH
		Maintainer: $MAINTAINER <$MAINTAINERMAIL>
		Installed-Size: 1
		Section: xorg
		Priority: optional
		Provides: armbian-bsp-desktop, armbian-bsp-desktop-${BOARD}
		Depends: ${BSP_CLI_PACKAGE_NAME}
		Description: Armbian Board Specific Packages for desktop users using $ARCH ${BOARD} machines
	EOF

	# Recreating the DEBIAN/postinst file
	echo "#!/bin/bash -e" > "${destination}/DEBIAN/postinst"
	echo "${AGGREGATED_DESKTOP_BSP_POSTINST}" >> "${destination}/DEBIAN/postinst"
	echo "exit 0" >> "${destination}/DEBIAN/postinst"
	chmod 755 "${destination}"/DEBIAN/postinst

	# Armbian create_desktop_package scripts
	mkdir -p "${destination}"/etc/armbian
	# @TODO: error information? This is very likely to explode....
	eval "${AGGREGATED_DESKTOP_BSP_PREPARE}"

	mkdir -p "${DEB_STORAGE}/${RELEASE}"
	cd "${destination}" || exit_with_error "Failed to cd to ${destination}"
	cd ..
	fakeroot_dpkg_deb_build "${destination}" "${DEB_STORAGE}/${RELEASE}"

	done_with_temp_dir "${cleanup_id}" # changes cwd to "${SRC}" and fires the cleanup function early
}
