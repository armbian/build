post_debootstrap_tweaks()
{

	# remove service start blockers and QEMU binary
	rm -f "${SDCARD}"/sbin/initctl "${SDCARD}"/sbin/start-stop-daemon
	chroot "${SDCARD}" /bin/bash -c "dpkg-divert --quiet --local --rename --remove /sbin/initctl"
	chroot "${SDCARD}" /bin/bash -c "dpkg-divert --quiet --local --rename --remove /sbin/start-stop-daemon"
	rm -f "${SDCARD}"/usr/sbin/policy-rc.d "${SDCARD}/usr/bin/${QEMU_BINARY}"

	call_extension_method "post_post_debootstrap_tweaks" "config_post_debootstrap_tweaks" << 'POST_POST_DEBOOTSTRAP_TWEAKS'
*run after removing diversions and qemu with chroot unmounted*
Last chance to touch the `${SDCARD}` filesystem before it is copied to the final media.
It is too late to run any chrooted commands, since the supporting filesystems are already unmounted.
POST_POST_DEBOOTSTRAP_TWEAKS

}
