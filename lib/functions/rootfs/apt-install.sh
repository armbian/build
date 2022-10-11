apt_purge_unneeded_packages() {
	# remove packages that are no longer needed. rootfs cache + uninstall might have leftovers.
	display_alert "No longer needed packages" "purge" "info"
	chroot_sdcard_apt_get autoremove
}

# this is called:
# 1) install_deb_chroot "${DEB_STORAGE}/somethingsomething.deb" (yes, it's always ${DEB_STORAGE})
# 2) install_deb_chroot "linux-u-boot-${BOARD}-${BRANCH}" "remote" (normal invocation, install from repo)
# 3) install_deb_chroot "linux-u-boot-${BOARD}-${BRANCH}" "remote" "yes" (install from repo, then also copy the WHOLE CACHE back to DEB_STORAGE)
install_deb_chroot() {
	local package="$1"
	local variant="$2"
	local transfer="$3"
	local install_target="${package}"
	local log_extra=" from repository"
	local package_filename
	package_filename="$(basename "${package}")"

	# For the local case.
	if [[ "${variant}" != "remote" ]]; then
		log_extra=""
		# @TODO: this can be sped up significantly by mounting debs readonly directly in chroot /root/debs and installing from there
		# also won't require cleanup later

		install_target="/root/${package_filename}"
		[[ ! -f "${SDCARD}${install_target}" ]] && run_host_command_logged cp -pv "${package}" "${SDCARD}${install_target}"
	fi

	display_alert "Installing${log_extra}" "${package_filename}" "debinstall" # This needs its own level

	# install in chroot via apt-get, not dpkg, so dependencies are also installed from repo if needed.
	export if_error_detail_message="Installation of $install_target failed ${BOARD} ${RELEASE} ${BUILD_DESKTOP} ${LINUXFAMILY}"
	DONT_MAINTAIN_APT_CACHE="yes" chroot_sdcard_apt_get --no-install-recommends install "${install_target}" # don't auto-maintain apt cache when installing from packages.

	# @TODO: mysterious. store installed/downloaded packages in deb storage. only used for u-boot deb. why?
	# this is some contrived way to get the uboot.deb when installing from repo; image builder needs the deb to be able to deploy uboot  later, even though it is already installed inside the chroot, it needs deb to be in host to reuse code later
	if [[ ${variant} == remote && ${transfer} == yes ]]; then
		display_alert "install_deb_chroot called with" "transfer=yes, copy WHOLE CACHE back to DEB_STORAGE, this is probably a bug" "warn"
		run_host_command_logged rsync -r "${SDCARD}"/var/cache/apt/archives/*.deb "${DEB_STORAGE}"/
	fi

	# IMPORTANT! Do not use short-circuit above as last statement in a function, since it determines the result of the function.
	return 0
}
