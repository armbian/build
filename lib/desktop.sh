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
	# Remove leading and trailing whitespaces
	display_alert "Showing PACKAGE_LIST_DESKTOP before postprocessing"
	# Use quotes to show leading and trailing spaces
	echo "\"$PACKAGE_LIST_DESKTOP\""

	# Remove leading and trailing spaces with some bash monstruosity
	# https://stackoverflow.com/questions/369758/how-to-trim-whitespace-from-a-bash-variable#12973694>
	PACKAGE_LIST_DESKTOP="${PACKAGE_LIST_DESKTOP#"${PACKAGE_LIST_DESKTOP%%[![:space:]]*}"}"
	PACKAGE_LIST_DESKTOP="${PACKAGE_LIST_DESKTOP%"${PACKAGE_LIST_DESKTOP##*[![:space:]]}"}"
	# Replace whitespace characters by commas
	PACKAGE_LIST_DESKTOP=${PACKAGE_LIST_DESKTOP// /,};
	# Remove others 'spacing characters' (like tabs)
	PACKAGE_LIST_DESKTOP=${PACKAGE_LIST_DESKTOP//[[:space:]]/}

	echo "PACKAGE_LIST_DESKTOP : ${PACKAGE_LIST_DESKTOP}"

	# Replace whitespace characters by commas
	PACKAGE_LIST_PREDEPENDS=${PACKAGE_LIST_PREDEPENDS// /,};
	# Remove others 'spacing characters' (like tabs)
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

	display_alert "Showing ${destination}/DEBIAN/control" 

	cat "${destination}"/DEBIAN/control

	# Recreating the DEBIAN/postinst file
	echo "#!/bin/sh -e" > "${destination}/DEBIAN/postinst"

	local aggregated_content=""
	aggregate_all "debian/postinst" $'\n'

	echo "${aggregated_content}" >> "${destination}/DEBIAN/postinst"
	echo "exit 0" >> "${destination}/DEBIAN/postinst"

	chmod 755 "${destination}"/DEBIAN/postinst

	display_alert "Showing ${destination}/DEBIAN/postinst"
	cat "${destination}/DEBIAN/postinst"

	# Armbian create_desktop_package scripts

	unset aggregated_content

	# Myy : I'm preparing the common armbian folders, in advance, since the scripts are now splitted
	mkdir -p "${destination}"/etc/armbian

	local aggregated_content=""

	aggregate_all "armbian/create_desktop_package.sh" $'\n'

	display_alert "Showing the user scripts executed in create_desktop_package"
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
