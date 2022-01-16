apt_purge_unneeded_packages() {
	# remove packages that are no longer needed. rootfs cache + uninstall might have leftovers.
	display_alert "No longer needed packages" "purge" "info"
	chroot_sdcard_apt_get autoremove
}
# this is called by distributions.sh->install_common(), and thus already under a logging manager.
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
		[[ ! -f "${SDCARD}${name}" ]] && cp "${package}" "${SDCARD}${name}"
		desc=""
	else
		name=$1
		desc=" from repository"
	fi

	# @TODO: this is mostly duplicated in distributions.sh->install_common(), refactor into "chroot_apt_get()"
	display_alert "Installing${desc}" "${name/\/root\//}"
	[[ $NO_APT_CACHER != yes ]] && local apt_extra="-o Acquire::http::Proxy=\"http://${APT_PROXY_ADDR:-localhost:3142}\" -o Acquire::http::Proxy::localhost=\"DIRECT\""
	# when building in bulk from remote, lets make sure we have up2date index
	[[ $BUILD_ALL == yes && ${variant} == remote ]] && chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get $apt_extra -yqq update"

	# install in chroot via apt-get, not dpkg, so dependencies are also installed from repo if needed.
	chroot_sdcard_apt_get --no-install-recommends install "${name}" || {
		exit_with_error "Installation of $name failed" "${BOARD} ${RELEASE} ${BUILD_DESKTOP} ${LINUXFAMILY}"
	}

	# @TODO: mysterious. store installed/downloaded packages in deb storage. only used for u-boot deb. why?
	[[ ${variant} == remote && ${transfer} == yes ]] && rsync -rq "${SDCARD}"/var/cache/apt/archives/*.deb ${DEB_STORAGE}/

	# IMPORTANT! Do not use conditional above as last statement in a function, since it determines the result of the function.
	return 0
}
