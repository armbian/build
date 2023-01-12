compile_firmware() {
	display_alert "Merging and packaging linux firmware" "@host" "info"

	local firmwaretempdir plugin_dir

	firmwaretempdir=$(mktemp -d) # subject to TMPDIR/WORKDIR, so is protected by single/common error trapmanager to clean-up.
	chmod 700 "${firmwaretempdir}"

	plugin_dir="armbian-firmware${FULL}"
	mkdir -p "${firmwaretempdir}/${plugin_dir}/lib/firmware"

	local ARMBIAN_FIRMWARE_GIT_SOURCE="${ARMBIAN_FIRMWARE_GIT_SOURCE:-"https://github.com/armbian/firmware"}"
	local ARMBIAN_FIRMWARE_GIT_BRANCH="${ARMBIAN_FIRMWARE_GIT_BRANCH:-"master"}"

	fetch_from_repo "${ARMBIAN_FIRMWARE_GIT_SOURCE}" "armbian-firmware-git" "branch:${ARMBIAN_FIRMWARE_GIT_BRANCH}"

	if [[ -n $FULL ]]; then
		fetch_from_repo "$MAINLINE_FIRMWARE_SOURCE" "linux-firmware-git" "branch:main"
		
		# @TODO: rpardini: what is this thing with hardlinks? why?
		# cp : create hardlinks
		run_host_command_logged cp -af --reflink=auto "${SRC}/cache/sources/linux-firmware-git/*" "${firmwaretempdir}/${plugin_dir}/lib/firmware/"
		# cp : create hardlinks for ath11k WCN685x hw2.1 firmware since they are using the same firmware with hw2.0
		run_host_command_logged cp -af --reflink=auto "${firmwaretempdir}/${plugin_dir}/lib/firmware/ath11k/WCN6855/hw2.0/" "${firmwaretempdir}/${plugin_dir}/lib/firmware/ath11k/WCN6855/hw2.1/"
	fi
	
	# overlay Armbian's firmware on top of the mainline firmware
	run_host_command_logged cp -af --reflink=auto "${SRC}/cache/sources/armbian-firmware-git/*" "${firmwaretempdir}/${plugin_dir}/lib/firmware/"

	rm -rf "${firmwaretempdir}/${plugin_dir}"/lib/firmware/.git # @TODO: would have been better waste I/O putting in there
	cd "${firmwaretempdir}/${plugin_dir}" || exit_with_error "can't change directory"

	# set up control file
	mkdir -p DEBIAN
	# @TODO: rpardini: this needs Conflicts: with the standard Ubuntu/Debian linux-firmware packages and other firmware pkgs in Debian
	cat <<- END > DEBIAN/control
		Package: armbian-firmware${FULL}
		Version: $REVISION
		Architecture: all
		Maintainer: $MAINTAINER <$MAINTAINERMAIL>
		Installed-Size: 1
		Replaces: linux-firmware, firmware-brcm80211, firmware-ralink, firmware-samsung, firmware-realtek, armbian-firmware${REPLACE}
		Section: kernel
		Priority: optional
		Description: Armbian - Linux firmware${FULL}
	END

	cd "${firmwaretempdir}" || exit_with_error "can't change directory"
	# pack
	mv "armbian-firmware${FULL}" "armbian-firmware${FULL}_${REVISION}_all"
	display_alert "Building firmware package" "armbian-firmware${FULL}_${REVISION}_all" "info"
	fakeroot_dpkg_deb_build "armbian-firmware${FULL}_${REVISION}_all"
	mv "armbian-firmware${FULL}_${REVISION}_all" "armbian-firmware${FULL}"
	run_host_command_logged rsync -rq "armbian-firmware${FULL}_${REVISION}_all.deb" "${DEB_STORAGE}/"
}
