#!/usr/bin/env bash

function create_desktop_package() {
	# produced by aggregation.py
	display_alert "bsp-desktop: AGGREGATED_PACKAGES_DESKTOP_COMMA" "'${AGGREGATED_PACKAGES_DESKTOP_COMMA}'" "debug"

	declare cleanup_id="" tmp_dir=""
	prepare_temp_dir_in_workdir_and_schedule_cleanup "bsp-desktop" cleanup_id tmp_dir # namerefs

	declare destination="${tmp_dir}/${BOARD}/${CHOSEN_DESKTOP}_${REVISION}_all"
	rm -rf "${destination}"
	mkdir -p "${destination}"/DEBIAN

	# set up control file
	cat <<- EOF > "${destination}"/DEBIAN/control
		Package: ${CHOSEN_DESKTOP}
		Version: $REVISION
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

	display_alert "Building desktop package" "${CHOSEN_DESKTOP}_${REVISION}_all" "info"

	mkdir -p "${DEB_STORAGE}/${RELEASE}"
	cd "${destination}" || exit_with_error "Failed to cd to ${destination}"
	cd ..
	fakeroot_dpkg_deb_build "${destination}" "${DEB_STORAGE}/${RELEASE}/${CHOSEN_DESKTOP}_${REVISION}_all.deb"

	done_with_temp_dir "${cleanup_id}" # changes cwd to "${SRC}" and fires the cleanup function early
}

function create_bsp_desktop_package() {
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
		Version: $REVISION
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
	fakeroot_dpkg_deb_build "${destination}" "${DEB_STORAGE}/${RELEASE}/${package_name}.deb"

	done_with_temp_dir "${cleanup_id}" # changes cwd to "${SRC}" and fires the cleanup function early
}
