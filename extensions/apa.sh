# Install armbian-common etc. from APA

function extension_prepare_config__apa() {
	display_alert "Target image will have Armbian Package Archive (APA) enabled by default" "${EXTENSION}" "info"
	export APA_IS_ACTIVE="true"
}

function custom_apt_repo__add_apa() {
	run_host_command_logged echo "deb [signed-by=${APT_SIGNING_KEY_FILE}] http://github.armbian.com/apa current main" "|" tee "${SDCARD}"/etc/apt/sources.list.d/armbian-apa.list
}

# this variable is a temporary hack, remove as soon as it's not needed
declare -g apa_additional_packages="libpam-systemd dbus-user-session curl iw less locales"
function post_debootstrap_install_additional_packages__install_from_apa_stage1() { #FIXME: we need a better hook that fits into the extensions system
	[[ $APA_IS_ACTIVE ]] || return 0

	# do not install armbian recommends for minimal images
	[[ "${BUILD_MINIMAL,,}" =~ ^(true|yes)$ ]] && INSTALL_RECOMMENDS="no-install-recommends" || INSTALL_RECOMMENDS="install-recommends"
	display_alert "installing armbian-common and friends" "APA: armbian-common $apa_additional_packages" "info"
	chroot_sdcard_apt_get install --$INSTALL_RECOMMENDS armbian-common $apa_additional_packages
	chroot_sdcard rm -f /etc/apt/sources.list.d/armbian-apa.list.inactive

	# install desktop environment if requested
	case ${DESKTOP_ENVIRONMENT^^} in
		XFCE|KDE|GNOME)
			display_alert "installing ${DESKTOP_ENVIRONMENT^^} desktop environment" "${EXTENSION}: ${DESKTOP_ENVIRONMENT^^}" "info"
			chroot_sdcard_apt_get install --install-recommends=yes "armbian-desktop-${DESKTOP_ENVIRONMENT,,}"
			;;
	esac
}

function post_armbian_repo_customize_image__install_from_apa_stage2() {
	# do not install armbian recommends for minimal images
	[[ "${BUILD_MINIMAL,,}" =~ ^(true|yes)$ ]] && INSTALL_RECOMMENDS="no-install-recommends" || INSTALL_RECOMMENDS="install-recommends"
	display_alert "installing armbian-bsp" "APA" "info"
	chroot_sdcard_apt_get install --$INSTALL_RECOMMENDS armbian-bsp
}
