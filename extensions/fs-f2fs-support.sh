# `f2fs` support is no longer included by default in prepare-host.sh.
# Enable this extension to include the required dependencies for building.
# This is automatically enabled if ROOTFS_TYPE is set to f2fs in main-config.sh.

function add_host_dependencies__add_f2fs_tooling() {
	display_alert "Adding F2FS to host dependencies" "F2FS" "debug"
	EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} f2fs-tools" # @TODO: convert to array later
}
