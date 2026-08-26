# @description Enables the Armbian Package Archive (APA) in the target image by setting `APA_IS_ACTIVE` and adding the `github.armbian.com/apa` apt repository. Installs `armbian-common` and `armbian-bsp` from it, plus the matching `armbian-desktop-*` metapackage when a `DESKTOP_ENVIRONMENT` (XFCE/KDE/GNOME) is selected. Enable it to source Armbian's core packages from APA by default.

# Install armbian-common etc. from APA

function extension_prepare_config__apa() {
	display_alert "Target image will have Armbian Package Archive (APA) enabled by default" "${EXTENSION}" "info"
	export APA_IS_ACTIVE="true"
}

function custom_apt_repo__add_apa() {
	run_host_command_logged echo "deb [signed-by=${APT_SIGNING_KEY_FILE}] http://github.armbian.com/apa current main" "|" tee "${SDCARD}"/etc/apt/sources.list.d/armbian-apa.list
}

function post_armbian_repo_customize_image__install_from_apa() {
	# do not install armbian recommends for minimal images
	[[ "${BUILD_MINIMAL,,}" =~ ^(true|yes)$ ]] && INSTALL_RECOMMENDS="no-install-recommends" || INSTALL_RECOMMENDS="install-recommends"
	chroot_sdcard_apt_get install --$INSTALL_RECOMMENDS armbian-common armbian-bsp
	chroot_sdcard rm -f /etc/apt/sources.list.d/armbian-apa.list.inactive

	# install desktop environment if requested
	case ${DESKTOP_ENVIRONMENT^^} in
		XFCE | KDE | GNOME)
			display_alert "installing ${DESKTOP_ENVIRONMENT^^} desktop environment" "${EXTENSION}: ${DESKTOP_ENVIRONMENT^^}" "info"
			chroot_sdcard_apt_get install --install-recommends=yes "armbian-desktop-${DESKTOP_ENVIRONMENT,,}"
			;;
	esac
}
