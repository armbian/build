# @description Adds NILFS2 root-filesystem support. Installs `nilfs-tools` into both the image and the host build dependencies, and appends the `nilfs2` module to `/etc/initramfs-tools/modules` so the log-structured filesystem can be mounted at boot. Auto-enabled when `ROOTFS_TYPE=nilfs2` in `main-config.sh`.

# Enable this extension to include the required dependencies for building.
# This is automatically enabled if ROOTFS_TYPE is set to nilfs2 in main-config.sh.

function extension_prepare_config__add_to_image_nilfs-tools() {
	display_alert "Extension: ${EXTENSION}: Adding extra packages to image" "nilfs-tools" "info"
	add_packages_to_image nilfs-tools
}

function add_host_dependencies__add_nilfs_tools() {
	display_alert "Extension: ${EXTENSION}: Adding packages to host dependencies" "nilfs-tools" "debug"
	EXTRA_BUILD_DEPS+=("fs-tools::nilfs-tools")
}

function pre_update_initramfs__add_module_into_initramfs_config() {
	echo "nilfs2" >> "$MOUNT"/etc/initramfs-tools/modules
	return 0
}
