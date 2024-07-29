#
# Extension to manage network time synchronization with systemd-timesyncd
#
function extension_prepare_config__install_systemd-timesyncd() {
	display_alert "Extension: ${EXTENSION}: Adding extra packages to image" "systemd-timesyncd" "info"
	add_packages_to_image systemd-timesyncd
}

function pre_install_kernel_debs__configure_systemd-timesyncd() {
	# Enable timesyncd
	display_alert "Extension: ${EXTENSION}: Enabling systemd-timesyncd" "" "info"
	chroot_sdcard systemctl enable systemd-timesyncd.service
}
