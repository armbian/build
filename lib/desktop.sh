#!/bin/bash

# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# Functions:
# create_desktop_package
# run_on_sdcard
# install_ppa_prerequisites
# add_apt_sources
# add_desktop_package_sources
# desktop_postinstall




create_desktop_package ()
{

	# join and cleanup package list
	# Remove leading and trailing whitespaces
	echo "Showing PACKAGE_LIST_DESKTOP before postprocessing" >> "${DEST}"/debug/output.log
	# Use quotes to show leading and trailing spaces
	echo "\"$PACKAGE_LIST_DESKTOP\"" >> "${DEST}"/debug/output.log

	# Remove leading and trailing spaces with some bash monstruosity
	# https://stackoverflow.com/questions/369758/how-to-trim-whitespace-from-a-bash-variable#12973694
	DEBIAN_RECOMMENDS="${PACKAGE_LIST_DESKTOP#"${PACKAGE_LIST_DESKTOP%%[![:space:]]*}"}"
	DEBIAN_RECOMMENDS="${DEBIAN_RECOMMENDS%"${DEBIAN_RECOMMENDS##*[![:space:]]}"}"
	# Replace whitespace characters by commas
	DEBIAN_RECOMMENDS=${DEBIAN_RECOMMENDS// /,};
	# Remove others 'spacing characters' (like tabs)
	DEBIAN_RECOMMENDS=${DEBIAN_RECOMMENDS//[[:space:]]/}

	echo "DEBIAN_RECOMMENDS : ${DEBIAN_RECOMMENDS}" >> "${DEST}"/debug/output.log

	# Replace whitespace characters by commas
	PACKAGE_LIST_PREDEPENDS=${PACKAGE_LIST_PREDEPENDS// /,};
	# Remove others 'spacing characters' (like tabs)
	PACKAGE_LIST_PREDEPENDS=${PACKAGE_LIST_PREDEPENDS//[[:space:]]/}

	local destination tmp_dir
	tmp_dir=$(mktemp -d)
	destination=${tmp_dir}/${BOARD}/${CHOSEN_DESKTOP}_${REVISION}_all
	rm -rf "${destination}"
	mkdir -p "${destination}"/DEBIAN

	echo "${PACKAGE_LIST_PREDEPENDS}" >> "${DEST}"/debug/output.log

	# set up control file
	cat <<-EOF > "${destination}"/DEBIAN/control
	Package: ${CHOSEN_DESKTOP}
	Version: $REVISION
	Architecture: all
	Maintainer: $MAINTAINER <$MAINTAINERMAIL>
	Installed-Size: 1
	Section: xorg
	Priority: optional
	Recommends: ${DEBIAN_RECOMMENDS//[:space:]+/,}
	Provides: ${CHOSEN_DESKTOP}, armbian-${RELEASE}-desktop
	Pre-Depends: ${PACKAGE_LIST_PREDEPENDS//[:space:]+/,}
	Description: Armbian desktop for ${DISTRIBUTION} ${RELEASE}
	EOF

	#display_alert "Showing ${destination}/DEBIAN/control"
	cat "${destination}"/DEBIAN/control >> "${DEST}"/debug/install.log

	# Recreating the DEBIAN/postinst file
	echo "#!/bin/sh -e" > "${destination}/DEBIAN/postinst"

	local aggregated_content=""
	aggregate_all "debian/postinst" $'\n'

	echo "${aggregated_content}" >> "${destination}/DEBIAN/postinst"
	echo "exit 0" >> "${destination}/DEBIAN/postinst"

	chmod 755 "${destination}"/DEBIAN/postinst

	#display_alert "Showing ${destination}/DEBIAN/postinst"
	cat "${destination}/DEBIAN/postinst" >> "${DEST}"/debug/install.log

	# Armbian create_desktop_package scripts

	unset aggregated_content

	# Myy : I'm preparing the common armbian folders, in advance, since the scripts are now splitted
	mkdir -p "${destination}"/etc/armbian

	local aggregated_content=""

	aggregate_all "armbian/create_desktop_package.sh" $'\n'

	# display_alert "Showing the user scripts executed in create_desktop_package"
	echo "${aggregated_content}" >> "${DEST}"/debug/install.log
	eval "${aggregated_content}"

	# create board DEB file
	display_alert "Building desktop package" "${CHOSEN_DESKTOP}_${REVISION}_all" "info"

	mkdir -p "${DEB_STORAGE}/${RELEASE}"
	cd "${destination}"; cd ..
	fakeroot dpkg-deb -b "${destination}" "${DEB_STORAGE}/${RELEASE}/${CHOSEN_DESKTOP}_${REVISION}_all.deb"  >/dev/null

	# cleanup
	rm -rf "${tmp_dir}"

	unset aggregated_content

}




run_on_sdcard() {

	# Myy : The lack of quotes is deliberate here
	# This allows for redirections and pipes easily.
	chroot "${SDCARD}" /bin/bash -c "${@}" >> "${DEST}"/debug/install.log

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
	get_all_potential_paths_for "sources/apt"

	display_alert "ADDING ADDITIONAL APT SOURCES"

	for apt_sources_dirpath in ${potential_paths}; do
		if [[ -d "${apt_sources_dirpath}" ]]; then
			for apt_source_filepath in "${apt_sources_dirpath}/"*.source; do
				local new_apt_source="$(cat "${apt_source_filepath}")"
				display_alert "Adding APT Source ${new_apt_source}"
				# -y -> Assumes yes to all queries
				# -n -> Do not update package cache after adding
				run_on_sdcard "add-apt-repository -y -n \"${new_apt_source}\""
				display_alert "Return code : $?" # (´・ω・｀)

				local apt_source_gpg_filepath="${apt_source_filepath}.gpg"

				# PPA provide GPG keys automatically, it seems.
				# But other repositories (Docker for example) require the
				# user to import GPG keys manually
				# Myy : FIXME We need some automatic Git warnings when someone
				# add a GPG key, since trusting the wrong keys could lead to
				# serious issues.
				if [[ -f "${apt_source_gpg_filepath}" ]]; then
					display_alert "Adding GPG Key ${apt_source_gpg_filepath}"
					local apt_source_gpg_filename="$(basename ${apt_source_gpg_filepath})"
					cp "${apt_source_gpg_filepath}" "${SDCARD}/tmp/${apt_source_gpg_filename}"
					run_on_sdcard "apt-key add \"/tmp/${apt_source_gpg_filename}\""
					echo "APT Key returned : $?"
				fi
			done
		fi
	done

}




add_desktop_package_sources() {

	# Myy : I see Snap and Flatpak coming up in the next releases
	# so... let's prepare for that
	# install_ppa_prerequisites # Myy : I'm currently trying to avoid adding "hidden" packages
	add_apt_sources
	run_on_sdcard "apt -y -q update"
	ls -l "${SDCARD}/etc/apt/sources.list.d" >> "${DEST}"/debug/install.log
	cat "${SDCARD}/etc/apt/sources.list" >> "${DEST}"/debug/install.log

}




desktop_postinstall ()
{

	# disable display manager for the first run
	run_on_sdcard "systemctl --no-reload disable lightdm.service >/dev/null 2>&1"
	run_on_sdcard "systemctl --no-reload disable gdm3.service >/dev/null 2>&1"
	run_on_sdcard "DEBIAN_FRONTEND=noninteractive apt-get update" >> "${DEST}"/debug/install.log

	if [[ -n ${PACKAGE_LIST_DESKTOP_BOARD} ]]; then
		run_on_sdcard "DEBIAN_FRONTEND=noninteractive  apt-get -yqq --no-install-recommends install $PACKAGE_LIST_DESKTOP_BOARD" 
	fi

	if [[ -n ${PACKAGE_LIST_DESKTOP_FAMILY} ]]; then
		run_on_sdcard "DEBIAN_FRONTEND=noninteractive apt-get -yqq --no-install-recommends install $PACKAGE_LIST_DESKTOP_FAMILY"
	fi

}