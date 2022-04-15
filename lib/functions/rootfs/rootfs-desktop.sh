# a-kind-of-hook, called by install_distribution_agnostic() if it's a desktop build
desktop_postinstall() {

	# disable display manager for the first run
	chroot_sdcard "systemctl --no-reload disable lightdm.service"
	chroot_sdcard "systemctl --no-reload disable gdm3.service"

	# update packages index
	chroot_sdcard_apt_get "update"

	# install per board packages
	if [[ -n ${PACKAGE_LIST_DESKTOP_BOARD} ]]; then
		chroot_sdcard_apt_get_install "$PACKAGE_LIST_DESKTOP_BOARD"
	fi

	# install per family packages
	if [[ -n ${PACKAGE_LIST_DESKTOP_FAMILY} ]]; then
		chroot_sdcard_apt_get_install "$PACKAGE_LIST_DESKTOP_FAMILY"
	fi

}
