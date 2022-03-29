#!/bin/bash
#
# Copyright (c) 2013-2021 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# Functions:

# create_desktop_package
# install_ppa_prerequisites
# add_apt_sources
# add_desktop_package_sources
# desktop_postinstall




create_desktop_package ()
{

	echo "Showing PACKAGE_LIST_DESKTOP before postprocessing" >> "${DEST}"/${LOG_SUBPATH}/output.log
	# Use quotes to show leading and trailing spaces
	echo "\"$PACKAGE_LIST_DESKTOP\"" >> "${DEST}"/${LOG_SUBPATH}/output.log

	# Remove leading and trailing spaces with some bash monstruosity
	# https://stackoverflow.com/questions/369758/how-to-trim-whitespace-from-a-bash-variable#12973694
	DEBIAN_RECOMMENDS="${PACKAGE_LIST_DESKTOP#"${PACKAGE_LIST_DESKTOP%%[![:space:]]*}"}"
	DEBIAN_RECOMMENDS="${DEBIAN_RECOMMENDS%"${DEBIAN_RECOMMENDS##*[![:space:]]}"}"
	# Replace whitespace characters by commas
	DEBIAN_RECOMMENDS=${DEBIAN_RECOMMENDS// /,};
	# Remove others 'spacing characters' (like tabs)
	DEBIAN_RECOMMENDS=${DEBIAN_RECOMMENDS//[[:space:]]/}

	echo "DEBIAN_RECOMMENDS : ${DEBIAN_RECOMMENDS}" >> "${DEST}"/${LOG_SUBPATH}/output.log

	# Replace whitespace characters by commas
	PACKAGE_LIST_PREDEPENDS=${PACKAGE_LIST_PREDEPENDS// /,};
	# Remove others 'spacing characters' (like tabs)
	PACKAGE_LIST_PREDEPENDS=${PACKAGE_LIST_PREDEPENDS//[[:space:]]/}

	local destination tmp_dir
	tmp_dir=$(mktemp -d)
	destination=${tmp_dir}/${BOARD}/${CHOSEN_DESKTOP}_${REVISION}_all
	rm -rf "${destination}"
	mkdir -p "${destination}"/DEBIAN

	echo "${PACKAGE_LIST_PREDEPENDS}" >> "${DEST}"/${LOG_SUBPATH}/output.log

	# set up control file
	cat <<-EOF > "${destination}"/DEBIAN/control
	Package: ${CHOSEN_DESKTOP}
	Version: $REVISION
	Architecture: all
	Maintainer: $MAINTAINER <$MAINTAINERMAIL>
	Installed-Size: 1
	Section: xorg
	Priority: optional
	Recommends: ${DEBIAN_RECOMMENDS//[:space:]+/,}, armbian-bsp-desktop
	Provides: ${CHOSEN_DESKTOP}, armbian-${RELEASE}-desktop
	Pre-Depends: ${PACKAGE_LIST_PREDEPENDS//[:space:]+/,}
	Description: Armbian desktop for ${DISTRIBUTION} ${RELEASE}
	EOF

	# Recreating the DEBIAN/postinst file
	echo "#!/bin/sh -e" > "${destination}/DEBIAN/postinst"

	local aggregated_content=""
	aggregate_all_desktop "debian/postinst" $'\n'

	echo "${aggregated_content}" >> "${destination}/DEBIAN/postinst"
	echo "exit 0" >> "${destination}/DEBIAN/postinst"

	chmod 755 "${destination}"/DEBIAN/postinst

	#display_alert "Showing ${destination}/DEBIAN/postinst"
	cat "${destination}/DEBIAN/postinst" >> "${DEST}"/${LOG_SUBPATH}/install.log

	# Armbian create_desktop_package scripts

	unset aggregated_content

	mkdir -p "${destination}"/etc/armbian

	local aggregated_content=""
	aggregate_all_desktop "armbian/create_desktop_package.sh" $'\n'
	eval "${aggregated_content}"
	[[ $? -ne 0 ]] && display_alert "create_desktop_package.sh exec error" "" "wrn"

	display_alert "Building desktop package" "${CHOSEN_DESKTOP}_${REVISION}_all" "info"

	mkdir -p "${DEB_STORAGE}/${RELEASE}"
	cd "${destination}"; cd ..
	fakeroot dpkg-deb -b -Z${DEB_COMPRESS} "${destination}" "${DEB_STORAGE}/${RELEASE}/${CHOSEN_DESKTOP}_${REVISION}_all.deb"  >/dev/null

	# cleanup
	rm -rf "${tmp_dir}"

	unset aggregated_content

}




create_bsp_desktop_package ()
{

	display_alert "Creating board support package for desktop" "${package_name}" "info"

	local package_name="${BSP_DESKTOP_PACKAGE_FULLNAME}"

	local destination tmp_dir
	tmp_dir=$(mktemp -d)
	destination=${tmp_dir}/${BOARD}/${BSP_DESKTOP_PACKAGE_FULLNAME}
	rm -rf "${destination}"
	mkdir -p "${destination}"/DEBIAN

	copy_all_packages_files_for "bsp-desktop"

	# set up control file
	cat <<-EOF > "${destination}"/DEBIAN/control
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
	echo "#!/bin/sh -e" > "${destination}/DEBIAN/postinst"

	local aggregated_content=""
	aggregate_all_desktop "debian/armbian-bsp-desktop/postinst" $'\n'

	echo "${aggregated_content}" >> "${destination}/DEBIAN/postinst"
	echo "exit 0" >> "${destination}/DEBIAN/postinst"

	chmod 755 "${destination}"/DEBIAN/postinst

	# Armbian create_desktop_package scripts

	unset aggregated_content

	mkdir -p "${destination}"/etc/armbian

	local aggregated_content=""
	aggregate_all_desktop "debian/armbian-bsp-desktop/prepare.sh" $'\n'
	eval "${aggregated_content}"
	[[ $? -ne 0 ]] && display_alert "prepare.sh exec error" "" "wrn"

	mkdir -p "${DEB_STORAGE}/${RELEASE}"
	cd "${destination}"; cd ..
	fakeroot dpkg-deb -b -Z${DEB_COMPRESS} "${destination}" "${DEB_STORAGE}/${RELEASE}/${package_name}.deb"  >/dev/null

	# cleanup
	rm -rf "${tmp_dir}"

	unset aggregated_content

}




install_ppa_prerequisites() {

	# Myy : So... The whole idea is that, a good bunch of external sources
	# are PPA.
	# Adding PPA without add-apt-repository is poorly conveninent since
	# you need to reconstruct the URL by hand, and find the GPG key yourself.
	# add-apt-repository does that automatically, and in a way that allows you
	# to remove it cleanly through the same tool.

	# Myy : TODO Try to find a way to install this package only when
	# we encounter a PPA.
	run_on_sdcard "DEBIAN_FRONTEND=noninteractive apt install -yqq software-properties-common"

}




add_apt_sources() {

	local potential_paths=""
	local sub_dirs_to_check=". "
	if [[ ! -z "${SELECTED_CONFIGURATION+x}" ]]; then
		sub_dirs_to_check+="config_${SELECTED_CONFIGURATION}"
	fi
	get_all_potential_paths "${DEBOOTSTRAP_SEARCH_RELATIVE_DIRS}" "${sub_dirs_to_check}" "sources/apt"
	get_all_potential_paths "${CLI_SEARCH_RELATIVE_DIRS}" "${sub_dirs_to_check}" "sources/apt"
	get_all_potential_paths "${DESKTOP_ENVIRONMENTS_SEARCH_RELATIVE_DIRS}" "." "sources/apt"
	get_all_potential_paths "${DESKTOP_APPGROUPS_SEARCH_RELATIVE_DIRS}" "${DESKTOP_APPGROUPS_SELECTED}" "sources/apt"

	display_alert "Adding additional apt sources"

	for apt_sources_dirpath in ${potential_paths}; do
		if [[ -d "${apt_sources_dirpath}" ]]; then
			for apt_source_filepath in "${apt_sources_dirpath}/"*.source; do
				apt_source_filepath=$(echo $apt_source_filepath | sed -re 's/(^.*[^/])\.[^./]*$/\1/')
				local new_apt_source="$(cat "${apt_source_filepath}.source")"
				local apt_source_gpg_filepath="${apt_source_filepath}.gpg"

				# extract filenames
				local apt_source_gpg_filename="$(basename ${apt_source_gpg_filepath})"
				local apt_source_filename="$(basename ${apt_source_filepath}).list"

				display_alert "Adding APT Source ${new_apt_source}"

				if [[ "${new_apt_source}" == ppa* ]] ; then
					# ppa with software-common-properties
					run_on_sdcard "add-apt-repository -y -n \"${new_apt_source}\""
					# add list with apt-add
					# -y -> Assumes yes to all queries
					# -n -> Do not update package cache after adding
					if [[ -f "${apt_source_gpg_filepath}" ]]; then
						 display_alert "Adding GPG Key ${apt_source_gpg_filepath}"
						cp "${apt_source_gpg_filepath}" "${SDCARD}/tmp/${apt_source_gpg_filename}"
						run_on_sdcard "apt-key add \"/tmp/${apt_source_gpg_filename}\""
						echo "APT Key returned : $?"
					fi
				else
					# installation without software-common-properties, sources.list + key.gpg
					echo "${new_apt_source}" > "${SDCARD}/etc/apt/sources.list.d/${apt_source_filename}"
					if [[ -f "${apt_source_gpg_filepath}" ]]; then
						display_alert "Adding GPG Key ${apt_source_gpg_filepath}"
#						local apt_source_gpg_filename="$(basename ${apt_source_gpg_filepath})"
						mkdir -p "${SDCARD}"/usr/share/keyrings/
						cp "${apt_source_gpg_filepath}" "${SDCARD}"/usr/share/keyrings/
					fi

				fi

			done
		fi
	done

}




add_desktop_package_sources() {

	# Myy : I see Snap and Flatpak coming up in the next releases
	# so... let's prepare for that

	add_apt_sources

	ls -l "${SDCARD}/usr/share/keyrings" >> "${DEST}"/${LOG_SUBPATH}/install.log
	ls -l "${SDCARD}/etc/apt/sources.list.d" >> "${DEST}"/${LOG_SUBPATH}/install.log
	cat "${SDCARD}/etc/apt/sources.list" >> "${DEST}"/${LOG_SUBPATH}/install.log

}




desktop_postinstall ()
{

	# disable display manager for the first run
	run_on_sdcard "systemctl --no-reload disable lightdm.service >/dev/null 2>&1"
	run_on_sdcard "systemctl --no-reload disable gdm3.service >/dev/null 2>&1"

	# update packages index
	run_on_sdcard "DEBIAN_FRONTEND=noninteractive apt-get update >/dev/null 2>&1"

	# install per board packages
	if [[ -n ${PACKAGE_LIST_DESKTOP_BOARD} ]]; then
		run_on_sdcard "DEBIAN_FRONTEND=noninteractive  apt-get -yqq --no-install-recommends install $PACKAGE_LIST_DESKTOP_BOARD"
	fi

	# install per family packages
	if [[ -n ${PACKAGE_LIST_DESKTOP_FAMILY} ]]; then
		run_on_sdcard "DEBIAN_FRONTEND=noninteractive apt-get -yqq --no-install-recommends install $PACKAGE_LIST_DESKTOP_FAMILY"
	fi

}
