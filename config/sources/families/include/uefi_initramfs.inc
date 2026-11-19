#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
# Sourced by the UEFI families (uefi_common.inc) and uefi-arm64-dt.

# Smaller initramfs: GRUB reads it through the firmware, which is slow from USB.
# - zstd: smaller than gzip, and faster to unpack.
# - MODULES=dep: only the drivers of this machine. The image ships an initramfs
#   with most drivers. The first boot makes it again with MODULES=dep.
function post_family_tweaks__uefi_initramfs() {
	display_alert "${BOARDFAMILY}" "initramfs: zstd, MODULES=dep after the first boot" "info"
	echo "COMPRESS=zstd" > "${SDCARD}"/etc/initramfs-tools/conf.d/armbian-uefi.conf
	install -Dm755 "$SRC/packages/bsp/uefi/armbian-initramfs-dep" "${SDCARD}/usr/lib/armbian/armbian-initramfs-dep"
	install -Dm644 "$SRC/packages/bsp/uefi/armbian-initramfs-dep.service" "${SDCARD}/usr/lib/systemd/system/armbian-initramfs-dep.service"
	chroot_sdcard systemctl --no-reload enable armbian-initramfs-dep.service
}

# After the image initramfs is made: with MODULES=dep in the build, it would
# only have the drivers of the build host.
function pre_umount_final_image__uefi_initramfs_dep() {
	echo "MODULES=dep" >> "${MOUNT}"/etc/initramfs-tools/conf.d/armbian-uefi.conf
}
