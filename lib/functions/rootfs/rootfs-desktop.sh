#!/usr/bin/env bash

# a-kind-of-hook, called by install_distribution_agnostic() if it's a desktop build
desktop_postinstall() {

	# disable display manager for the first run
	disable_systemd_service_sdcard lightdm.service
	disable_systemd_service_sdcard gdm3.service

	# update packages index
	chroot_sdcard_apt_get "update"

	# @TODO: rpardini: this is... missing from aggregation...?
	# install per board packages
	if [[ -n ${PACKAGE_LIST_DESKTOP_BOARD} ]]; then
		chroot_sdcard_apt_get_install "$PACKAGE_LIST_DESKTOP_BOARD"
	fi

	# install per family packages
	if [[ -n ${PACKAGE_LIST_DESKTOP_FAMILY} ]]; then
		chroot_sdcard_apt_get_install "$PACKAGE_LIST_DESKTOP_FAMILY"
	fi

}
