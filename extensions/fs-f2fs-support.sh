# @description Adds F2FS filesystem support to the build host. Appends `f2fs-tools` to `EXTRA_BUILD_DEPS` so the required tooling is present when building an f2fs root, which is no longer bundled by `prepare-host.sh`. Auto-enabled when `ROOTFS_TYPE=f2fs` in `main-config.sh`.

# `f2fs` support is no longer included by default in prepare-host.sh.
# Enable this extension to include the required dependencies for building.
# This is automatically enabled if ROOTFS_TYPE is set to f2fs in main-config.sh.

function add_host_dependencies__add_f2fs_tooling() {
	display_alert "Extension: ${EXTENSION}: Adding packages to host dependencies" "f2fs-tools" "debug"
	EXTRA_BUILD_DEPS+=("fs-tools::f2fs-tools")
}
