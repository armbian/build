apt_purge_unneeded_packages() {
	# remove packages that are no longer needed. rootfs cache + uninstall might have leftovers.
	display_alert "No longer needed packages" "purge" "info"
	chroot_sdcard_apt_get autoremove
}

install_deb_chroot() {
	local package=$1
	local variant=$2
	local transfer=$3
	local name
	local desc

	if [[ ${variant} != remote ]]; then
		# @TODO: this can be sped up significantly by mounting debs readonly directly in chroot /root/debs and installing from there
		# also won't require cleanup later

		name="/root/"$(basename "${package}")
		[[ ! -f "${SDCARD}${name}" ]] && run_host_command_logged cp -pv "${package}" "${SDCARD}${name}"
		desc=""
	else
		name=$1
		desc=" from repository"
	fi

	display_alert "Installing${desc}" "${name/\/root\//}"

	# install in chroot via apt-get, not dpkg, so dependencies are also installed from repo if needed.
	export if_error_detail_message="Installation of $name failed ${BOARD} ${RELEASE} ${BUILD_DESKTOP} ${LINUXFAMILY}"
	chroot_sdcard_apt_get --no-install-recommends install "${name}"

	# @TODO: mysterious. store installed/downloaded packages in deb storage. only used for u-boot deb. why?
	[[ ${variant} == remote && ${transfer} == yes ]] && run_host_command_logged rsync -r "${SDCARD}"/var/cache/apt/archives/*.deb "${DEB_STORAGE}"/

	# IMPORTANT! Do not use short-circuit above as last statement in a function, since it determines the result of the function.
	return 0
}
