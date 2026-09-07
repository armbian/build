# @description Adds XFS root filesystem support, no longer bundled by default in `prepare-host.sh`. Installs `xfsprogs` into the image and adds it to the host build dependencies (`fs-tools::xfsprogs`) so the rootfs can be created. Auto-enabled when `ROOTFS_TYPE=xfs` is set in `main-config.sh`.

# `xfs` support is no longer included by default in prepare-host.sh.
# Enable this extension to include the required dependencies for building.
# This is automatically enabled if ROOTFS_TYPE is set to xfs in main-config.sh.

function extension_prepare_config__add_to_image_xfsprogs() {
	display_alert "Extension: ${EXTENSION}: Adding extra packages to image" "xfsprogs" "info"
	add_packages_to_image xfsprogs
}

function add_host_dependencies__add_xfs_tooling() {
	display_alert "Extension: ${EXTENSION}: Adding packages to host dependencies" "xfsprogs" "debug"
	EXTRA_BUILD_DEPS+=("fs-tools::xfsprogs")
}
