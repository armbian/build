# `btrfs` support is no longer included by default in prepare-host.sh.
# Enable this extension to include the required dependencies for building.
# This is automatically enabled if ROOTFS_TYPE is set to btrfs in main-config.sh.

function extension_prepare_config__add_to_image_btrfs-progs() {
	display_alert "Extension: ${EXTENSION}: Adding extra package to image" "btrfs-progs" "info"
	add_packages_to_image btrfs-progs
}

function add_host_dependencies__add_btrfs_tooling() {
	display_alert "Extension: ${EXTENSION}: Adding packages to host dependencies" "btrfs-progs" "debug"
	EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} btrfs-progs" # @TODO: convert to array later
}
