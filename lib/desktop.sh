#!/bin/bash

# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/



create_desktop_package ()
{
	# join and cleanup package list
	PACKAGE_LIST_DESKTOP=${PACKAGE_LIST_DESKTOP// /,};
	PACKAGE_LIST_DESKTOP=${PACKAGE_LIST_DESKTOP//[[:space:]]/}

	echo "PACKAGE_LIST_DESKTOP : ${PACKAGE_LIST_DESKTOP}"

	PACKAGE_LIST_PREDEPENDS=${PACKAGE_LIST_PREDEPENDS// /,};
	PACKAGE_LIST_PREDEPENDS=${PACKAGE_LIST_PREDEPENDS//[[:space:]]/}

	local destination=${SRC}/.tmp/${RELEASE}/${BOARD}/${CHOSEN_DESKTOP}_${REVISION}_all
	rm -rf "${destination}"
	mkdir -p "${destination}"/DEBIAN

	echo "${PACKAGE_LIST_PREDEPENDS}"

	# set up control file
	cat <<-EOF > "${destination}"/DEBIAN/control
	Package: ${CHOSEN_DESKTOP}
	Version: $REVISION
	Architecture: all
	Maintainer: $MAINTAINER <$MAINTAINERMAIL>
	Installed-Size: 1
	Section: xorg
	Priority: optional
	Recommends: ${PACKAGE_LIST_DESKTOP//[:space:]+/,}
	Provides: ${CHOSEN_DESKTOP}
	Pre-Depends: ${PACKAGE_LIST_PREDEPENDS//[:space:]+/,}
	Description: Armbian desktop for ${DISTRIBUTION} ${RELEASE}
	EOF

	# Recreating the DEBIAN/postinst file
	echo "#!/bin/sh -e" > "${destination}/DEBIAN/postinst"

	local aggregated_content=""
	aggregate_all "debian/postinst"

	#postinst_paths=""
	#postinst_paths+=" ${DESKTOP_ENVIRONMENT_DIRPATH}/debian/postinst"
	#postinst_paths+=" ${DESKTOP_ENVIRONMENT_DIRPATH}/affinities/${BOARD}/debian/postinst"
	#for software_group in ${DESKTOP_SOFTWARE_GROUPS_SELECTED}; do
	#	software_group_dirpath="${DESKTOP_SOFTWARE_GROUPS_DIR}/${software_group}"
	#	postinst_paths+=" ${software_group_dirpath}/debian/postinst"
	#	postinst_paths+=" ${software_group_dirpath}/affinities/${DESKTOP_ENVIRONMENT}/debian/postinst"
	#	postinst_paths+=" ${software_group_dirpath}/affinities/${BOARD}/debian/postinst"
	#done

	#echo "Parsed postinst_paths : ${postinst_paths}"
	#for postinst_filepath in ${postinst_paths}; do
	#	echo -n "${postinst_filepath} exist ? "
	#	if [[ -f "${postinst_filepath}" ]]; then
	#		echo "Yes"
	#		cat "${postinst_filepath}" >> "${destination}/DEBIAN/postinst"
	#		# Just in case the file doesn't end up with a carriage return, for "reasons"
	#		echo "" >> "${destination}/DEBIAN/postinst"
	#	else
	#		echo "Nope"
	#	fi
	#done

	# unset postinst_paths

	echo "${aggregated_content}" >> "${destination}/DEBIAN/postinst"
	echo "exit 0" >> "${destination}/DEBIAN/postinst"

	chmod 755 "${destination}"/DEBIAN/postinst

	cat "${destination}/DEBIAN/postinst"

	# Armbian create_desktop_package scripts

	unset aggregated_content

	# Myy : I'm preparing the common armbian folders, in advance, since the scripts are now splitted
	mkdir -p "${destination}"/etc/armbian

	local aggregated_content=""

	aggregate_all "armbian/create_desktop_package.sh"

	echo "${aggregated_content}"
	eval "${aggregated_content}"

	# create board DEB file
	display_alert "Building desktop package" "${CHOSEN_DESKTOP}_${REVISION}_all" "info"
	fakeroot dpkg-deb -b "${destination}" "${destination}.deb" >/dev/null
	mkdir -p "${DEB_STORAGE}/${RELEASE}"
	mv "${destination}.deb" "${DEB_STORAGE}/${RELEASE}"
	# cleanup
	rm -rf "${destination}"

	unset aggregated_content

}

desktop_postinstall ()
{
	# disable display manager for first run
	chroot "${SDCARD}" /bin/bash -c "systemctl --no-reload disable lightdm.service >/dev/null 2>&1"
	chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt update" >> "${DEST}"/debug/install.log
	#if [[ ${FULL_DESKTOP} == yes ]]; then
	#	chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive  apt -yqq --no-install-recommends install $PACKAGE_LIST_DESKTOP_FULL" >> "${DEST}"/debug/install.log
	#fi

	if [[ -n ${PACKAGE_LIST_DESKTOP_BOARD} ]]; then
		chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive  apt -yqq --no-install-recommends install $PACKAGE_LIST_DESKTOP_BOARD" >> "${DEST}"/debug/install.log
	fi

	if [[ -n ${PACKAGE_LIST_DESKTOP_FAMILY} ]]; then
		chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt -yqq --no-install-recommends install $PACKAGE_LIST_DESKTOP_FAMILY" >> "${DEST}"/debug/install.log
	fi

	# Compile Turbo Frame buffer for sunxi
	if [[ $LINUXFAMILY == sun* && $BRANCH == default ]]; then
		sed 's/name="use_compositing" type="bool" value="true"/name="use_compositing" type="bool" value="false"/' -i "${SDCARD}"/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml

		# enable memory reservations
		echo "disp_mem_reserves=on" >> "${SDCARD}"/boot/armbianEnv.txt
		echo "extraargs=cma=96M" >> "${SDCARD}"/boot/armbianEnv.txt
	fi
}
