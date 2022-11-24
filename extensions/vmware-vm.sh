enable_extension "image-output-ovf" # Enable the ovf+vmdk output image extension

function extension_prepare_config__prepare_vmware_config() {
	display_alert "Preparing VMWare extra packages..." "${EXTENSION}" "info"
	# Add VMWare utilities, for all
	add_packages_to_image open-vm-tools

	# If it's a desktop there's more
	if [[ $BUILD_DESKTOP == yes ]]; then
		display_alert "Preparing VMWare extra Desktop packages..." "${EXTENSION}" "info"
		add_packages_to_image open-vm-tools-desktop xserver-xorg-video-vmware
	fi
}
