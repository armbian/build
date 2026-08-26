# @description Builds a VMware-ready image by enabling the `image-output-ovf` extension (VMDK + OVF output) and installing `open-vm-tools` in the guest. On desktop builds it also adds `open-vm-tools-desktop` and the `xserver-xorg-video-vmware` driver for display integration. Enable it to run Armbian under VMware.

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
