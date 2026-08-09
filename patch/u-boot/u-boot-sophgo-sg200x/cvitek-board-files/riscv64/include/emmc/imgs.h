/* Armbian: hand-written, not an SDK mk_imgHeader.py output. See
 * u-boot.md in the milkv-duos-docs repo.
 *
 * The filenames cvi_update looks for in the FAT root of the installer SD card,
 * in the order it flashes them. Slot 0 is never read: both _storage_update()
 * and _uart_update() in cmd/cvi_update.c loop from index 1, because fip.bin is
 * handled ahead of the loop - it goes to the eMMC boot hardware partition
 * rather than to an offset in the user area. It is spelled out here anyway so
 * the list matches what actually ends up on the card.
 *
 * Where the vendor package has three entries (boot.emmc, logo.jpg,
 * rootfs_ext4.emmc) for its BOOT/MISC/ROOTFS split, Armbian has one. _prgImage()
 * writes each chunk to an absolute byte offset on the raw eMMC, so a single
 * payload starting at offset 0 can carry the whole disk - MBR, FAT /boot and
 * ext4 root exactly as they are on the SD image. That keeps the boot script, apt
 * kernel upgrades and first-boot resize working, none of which survive the
 * vendor layout, where /boot is a raw FIT partition with no filesystem.
 */

char imgs[][255] = {"fip.bin",
"armbian.emmc",
};
