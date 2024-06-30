#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
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

	# remove the qemu static binary
	undeploy_qemu_binary_from_chroot "${SDCARD}"

	call_extension_method "post_post_debootstrap_tweaks" "config_post_debootstrap_tweaks" <<- 'POST_POST_DEBOOTSTRAP_TWEAKS'
		*run after removing diversions and qemu with chroot unmounted*
		Last chance to touch the `${SDCARD}` filesystem before it is copied to the final media.
		It is too late to run any chrooted commands, since the supporting filesystems are already unmounted.
	POST_POST_DEBOOTSTRAP_TWEAKS
}
