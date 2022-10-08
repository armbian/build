desktop_postinstall() {

	# disable display manager for the first run
	run_on_sdcard "systemctl --no-reload disable lightdm.service >/dev/null 2>&1"
	run_on_sdcard "systemctl --no-reload disable gdm3.service >/dev/null 2>&1"

	# update packages index
	run_on_sdcard "DEBIAN_FRONTEND=noninteractive apt-get update >/dev/null 2>&1"

	# install per board packages
	if [[ -n ${PACKAGE_LIST_DESKTOP_BOARD} ]]; then
		run_on_sdcard "DEBIAN_FRONTEND=noninteractive  apt-get -yqq --no-install-recommends install $PACKAGE_LIST_DESKTOP_BOARD"
	fi

	# install per family packages
	if [[ -n ${PACKAGE_LIST_DESKTOP_FAMILY} ]]; then
		run_on_sdcard "DEBIAN_FRONTEND=noninteractive apt-get -yqq --no-install-recommends install $PACKAGE_LIST_DESKTOP_FAMILY"
	fi

}
