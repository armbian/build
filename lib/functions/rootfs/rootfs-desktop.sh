#!/usr/bin/env bash

# a-kind-of-hook, called by install_distribution_agnostic() if it's a desktop build
function desktop_postinstall() {

	# disable display manager for the first run
	disable_systemd_service_sdcard lightdm.service
	disable_systemd_service_sdcard gdm3.service

	# @TODO: why? 
	display_alert "Updating package lists" "for desktop" "info"
	do_with_retries 3 chroot_sdcard_apt_get_update

	# @TODO: rpardini: this is... missing from aggregation...? it is used by 2 boards.
	# install per board packages, desktop-only, packages.
	if [[ -n ${PACKAGE_LIST_DESKTOP_BOARD} ]]; then
		chroot_sdcard_apt_get_install "$PACKAGE_LIST_DESKTOP_BOARD"
	fi

	# install per family packages (desktop only)
	if [[ -n ${PACKAGE_LIST_DESKTOP_FAMILY} ]]; then # @TODO: used by 0 boards
		chroot_sdcard_apt_get_install "$PACKAGE_LIST_DESKTOP_FAMILY"
	fi

}
