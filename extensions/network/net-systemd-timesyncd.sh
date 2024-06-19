#
# Extension to manage network time synchronization with systemd-timesyncd
#
function add_host_dependencies__install_systemd-timesyncd() {
        display_alert "Extension: ${EXTENSION}: Installing additional packages" "systemd-timesyncd" "info"
        add_packages_to_rootfs systemd-timesyncd
}

function pre_install_kernel_debs__configure_systemd-timesyncd()
{
	# Enable timesyncd
	display_alert "Extension: ${EXTENSION}: Enabling systemd-timesyncd" "" "info"
	chroot_sdcard systemctl enable systemd-timesyncd.service
}
