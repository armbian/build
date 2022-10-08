install_deb_chroot() {

	local package=$1
	local variant=$2
	local transfer=$3
	local name
	local desc
	if [[ ${variant} != remote ]]; then
		name="/root/"$(basename "${package}")
		[[ ! -f "${SDCARD}${name}" ]] && cp "${package}" "${SDCARD}${name}"
		desc=""
	else
		name=$1
		desc=" from repository"
	fi

	display_alert "Installing${desc}" "${name/\/root\//}"
	[[ $NO_APT_CACHER != yes ]] && local apt_extra="-o Acquire::http::Proxy=\"http://${APT_PROXY_ADDR:-localhost:3142}\" -o Acquire::http::Proxy::localhost=\"DIRECT\""
	# when building in bulk from remote, lets make sure we have up2date index
	chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -yqq $apt_extra --no-install-recommends install $name" >> "${DEST}"/${LOG_SUBPATH}/install.log 2>&1
	[[ $? -ne 0 ]] && exit_with_error "Installation of $name failed" "${BOARD} ${RELEASE} ${BUILD_DESKTOP} ${LINUXFAMILY}"
	[[ ${variant} == remote && ${transfer} == yes ]] && rsync -rq "${SDCARD}"/var/cache/apt/archives/*.deb ${DEB_STORAGE}/

}
