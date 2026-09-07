# @description Adds Btrfs filesystem support, no longer bundled by default in `prepare-host.sh`. Appends `btrfs-progs` to both host build deps and the image packages, and injects the matching checksum module (`xxhash_generic` or `blake2b_generic`) into initramfs based on `BTRFS_CHECKSUM`. Auto-enabled when `ROOTFS_TYPE=btrfs` in `main-config.sh`.

# `btrfs` support is no longer included by default in prepare-host.sh.
# Enable this extension to include the required dependencies for building.
# This is automatically enabled if ROOTFS_TYPE is set to btrfs in main-config.sh.

function extension_prepare_config__add_to_image_btrfs-progs() {
	display_alert "Extension: ${EXTENSION}: Adding extra package to image" "btrfs-progs" "info"
	add_packages_to_image btrfs-progs
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
