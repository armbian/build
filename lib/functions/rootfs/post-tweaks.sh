#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function post_debootstrap_tweaks() {
	display_alert "Applying post-tweaks" "post_debootstrap_tweaks" "debug"

	# adjust tzselect to improve political correctness
	sed -i "s/Please select a country/Please select a country or a region/g" "${SDCARD}"/usr/bin/tzselect

	# activate systemd-resolved
	display_alert "Activating systemd-resolved" "Symlinking /etc/resolv.conf to /run/systemd/resolve/stub-resolv.conf" "debug"
	run_host_command_logged rm -fv "${SDCARD}"/etc/resolv.conf
	# The method of symlinking to /run/systemd/resolve/stub-resolv.conf is recommended, see https://www.man7.org/linux/man-pages/man8/systemd-resolved.service.8.html
	run_host_command_logged ln -s /run/systemd/resolve/stub-resolv.conf "${SDCARD}"/etc/resolv.conf

	# remove service start blockers
	run_host_command_logged rm -fv "${SDCARD}"/sbin/initctl "${SDCARD}"/sbin/start-stop-daemon
	chroot_sdcard dpkg-divert --quiet --local --rename --remove /sbin/initctl
	chroot_sdcard dpkg-divert --quiet --local --rename --remove /sbin/start-stop-daemon
	run_host_command_logged rm -fv "${SDCARD}"/usr/sbin/policy-rc.d

	# armbian-firstrun applies the tuning profile with armbian-config. Without it, the profile never applies.
	if [[ -f "${SDCARD}"/etc/default/armbian-tuning-profile && ! -x "${SDCARD}"/usr/bin/armbian-config ]]; then
		[[ -n "${TUNING_PROFILE}" ]] && exit_with_error "TUNING_PROFILE needs armbian-config in the image" "${TUNING_PROFILE}"
		display_alert "No armbian-config in the image" "skipping the tuning profile" "warn"
		run_host_command_logged rm -fv "${SDCARD}"/etc/default/armbian-tuning-profile
	fi

	call_extension_method "post_post_debootstrap_tweaks" "config_post_debootstrap_tweaks" <<- 'POST_POST_DEBOOTSTRAP_TWEAKS'
		*run after removing diversions and qemu with chroot unmounted*
		Last chance to touch the `${SDCARD}` filesystem before it is copied to the final media.
	POST_POST_DEBOOTSTRAP_TWEAKS

	return 0
}
