# `btrfs` support is no longer included by default in prepare-host.sh.
# Enable this extension to include the required dependencies for building.
# This is automatically enabled if ROOTFS_TYPE is set to btrfs in main-config.sh.

function add_host_dependencies__add_btrfs_tooling() {
	display_alert "Adding BTRFS to host dependencies" "BTRFS" "debug"
	EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} btrfs-progs" # @TODO: convert to array later
}
