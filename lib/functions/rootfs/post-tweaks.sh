#!/usr/bin/env bash

function post_debootstrap_tweaks() {
	display_alert "Applying post-tweaks" "post_debootstrap_tweaks" "debug"

	# activate systemd-resolved, if not using NetworkManager
	if [[ ! -f "${SDCARD}"/etc/NetworkManager/NetworkManager.conf ]]; then
		if [[ -d "${SDCARD}"/etc/systemd/network ]]; then
			display_alert "Activating systemd-resolved" "Symlink resolv.conf to systemd-resolved's" "debug"
			run_host_command_logged rm -fv "${SDCARD}"/etc/resolv.conf
			run_host_command_logged ln -s /run/systemd/resolve/resolv.conf "${SDCARD}"/etc/resolv.conf
		fi
	fi

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
