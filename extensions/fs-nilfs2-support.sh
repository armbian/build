# Enable this extension to include the required dependencies for building.
# This is automatically enabled if ROOTFS_TYPE is set to nilfs2 in main-config.sh.

function extension_prepare_config__add_to_image_nilfs-tools() {
	display_alert "Adding nilfs-tools extra package..." "${EXTENSION}" "info"
	add_packages_to_image nilfs-tools
}

function add_host_dependencies__add_nilfs_tools() {
	display_alert "Adding NILFS tools to host dependencies..." "${EXTENSION}" "debug"
	EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} nilfs-tools" # @TODO: convert to array later
}

function pre_update_initramfs__add_module_into_initramfs_config() {
	echo "nilfs2" >> "$MOUNT"/etc/initramfs-tools/modules
	return 0
}
