#!/usr/bin/env bash

#
# Armbian Optimizations for Low-Memory Boards
#
# Boards with less than *256MB* RAM need special optimizations to run Armbian smoothly.
# This extension applies the necessary *userland* (not-kernel) optimizations
# at build time.
#

function post_family_tweaks_bsp__copy_lowmem_config() {
	display_alert "${EXTENSION}" "Installing default configuration" "debug"

	# Copy /etc/default/armbian-lowmem configuration file
	# Allows user to customize swapfile size / location
	if [ ! -f "$destination/etc/default/armbian-lowmem" ]; then
		install -m 664 "$SRC/packages/bsp/armbian-lowmem/etc/default/armbian-lowmem.dpkg-dist" "$destination/etc/default/armbian-lowmem"
	fi

	return 0
}

function post_family_tweaks_bsp__copy_lowmem_mkswap() {
	local service_name="lowmem-mkswap"
	# Devices with very low memory need a swapfile to operate smoothly (apt, locale-gen, etc)
	display_alert "${EXTENSION}" "Installing ${service_name}.service" "debug"

	# Copy systemd service and script to create swapfile
	install -m 755 "$SRC/packages/bsp/armbian-lowmem/${service_name}.sh" "$destination/usr/bin/${service_name}.sh"
	install -m 644 "$SRC/packages/bsp/armbian-lowmem/${service_name}.service" "$destination/lib/systemd/system/${service_name}.service"

	return 0
}

function post_family_tweaks__enable_lowmem_mkswap() {
	local service_name="lowmem-mkswap"
	display_alert "${EXTENSION}" "Enabling ${service_name}.service" "debug"
	# This service disables itself after running once
	chroot_sdcard systemctl enable "${service_name}.service"

	return 0
}

function pre_umount_final_image__memory_optimize_defaults() {
	local LOWMEM_TMPFS_RUN_MB=${LOWMEM_TMPFS_RUN_MB:-20}
	# Optimize /etc/default settings to reduce memory usage
	display_alert "${EXTENSION}" "Disabling ramlog by default to save memory" "debug"
	sed -i "s/^ENABLED=.*/ENABLED=false/" "${MOUNT}"/etc/default/armbian-ramlog

	display_alert "${EXTENSION}" "Disabling zram swap by default" "debug"
	sed -i "s/^#\?\s*SWAP=.*/SWAP=false/" "${MOUNT}"/etc/default/armbian-zram-config

	# /run is 10% of RAM by default
	# systemd throws errors when <16MB is *free* in this partition
	# during daemon-reload operations.
	# Address with a fixed /run size of ${LOWMEM_TMPFS_RUN_MB}
	if ! grep -qE "tmpfs[[:space:]]+/run[[:space:]]+tmpfs" "${MOUNT}/etc/fstab"; then
		# Skip if /run entry already exists in fstab (userpatches, etc)
		display_alert "${EXTENSION}" "Fixing /run size in /etc/fstab" "debug"
		echo "tmpfs /run tmpfs rw,nosuid,nodev,noexec,relatime,size=${LOWMEM_TMPFS_RUN_MB}M,mode=755 0 0" >> "${MOUNT}"/etc/fstab
	fi

	return 0
}
