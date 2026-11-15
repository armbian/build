# @description Adds Btrfs filesystem support, no longer bundled by default in `prepare-host.sh`. Appends `btrfs-progs` to both host build deps and the image packages, installs `armbian-snapshots` from the Armbian repository, and injects the matching checksum module (`xxhash_generic` or `blake2b_generic`) into initramfs based on `BTRFS_CHECKSUM`. Auto-enabled when `ROOTFS_TYPE=btrfs` in `main-config.sh`.

# `btrfs` support is no longer included by default in prepare-host.sh.
# Enable this extension to include the required dependencies for building.
# This is automatically enabled if ROOTFS_TYPE is set to btrfs in main-config.sh.

function extension_prepare_config__add_to_image_btrfs-progs() {
	display_alert "Extension: ${EXTENSION}: Adding extra package to image" "btrfs-progs" "info"
	add_packages_to_image btrfs-progs
	# post_armbian_repo_customize_image does not run without the Armbian repository.
	if [[ "${SKIP_ARMBIAN_REPO}" == "yes" ]]; then
		display_alert "Extension: ${EXTENSION}" "SKIP_ARMBIAN_REPO=yes: armbian-snapshots not installed" "warn"
	fi
}

# armbian-snapshots (armbian/external): snapper snapshots before and after
# each package change. It comes from the Armbian repository, which the image
# stage enables only at image-late, so add_packages_to_image cannot install it.
function post_armbian_repo_customize_image__install_armbian_snapshots() {
	display_alert "Extension: ${EXTENSION}: Installing package" "armbian-snapshots" "info"
	chroot_sdcard_apt_get_install armbian-snapshots
}

function add_host_dependencies__add_btrfs_tooling() {
	display_alert "Extension: ${EXTENSION}: Adding packages to host dependencies" "btrfs-progs" "debug"
	EXTRA_BUILD_DEPS+=("fs-tools::btrfs-progs")
}

function pre_update_initramfs__add_compression_module_to_initramfs() {
	local modules=()
	case "$BTRFS_CHECKSUM" in
		xxhash) modules+=( xxhash_generic ) ;;
		blake2) modules+=( blake2b_generic ) ;;
		*) ;;
	esac
	if [[ "${#modules[@]}" -gt 0 ]]; then
		display_alert "Extension: ${EXTENSION}: Adding extra boot-time module(s)" "${modules[*]}" info
		printf '%s\n' "${modules[@]}" >> "$MOUNT"/etc/initramfs-tools/modules
	fi
}
