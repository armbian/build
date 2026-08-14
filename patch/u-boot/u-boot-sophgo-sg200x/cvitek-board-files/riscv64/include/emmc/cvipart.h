/* Armbian: hand-written, not an SDK mkcvipart.py output. See u-boot.md in
 * the milkv-duos-docs repo.
 *
 * PARTS_OFFSET below transcribes the vendor eMMC layout from
 * partition_emmc.xml as shipped in milkv-duos-emmc-v1.1.4, converted from the
 * XML's size_in_kb to the 512-byte sectors mkcvipart.py emits. The conversion
 * is confirmed by the vendor's own images: rootfs_ext4.emmc's first chunk
 * header carries destination offset 0xa20000, which is exactly
 * ROOTFS_PART_OFFSET (0x5100) * 512.
 *
 *   label   size_in_kb   offset (sectors)   size (sectors)
 *   BOOT        8192     0x0                0x4000
 *   MISC        2048     0x4000             0x1000
 *   ENV          128     0x5000             0x100
 *   ROOTFS    786560     0x5100             0x1800c0
 *
 * None of it is read on an Armbian boot. These values reach U-Boot as
 * environment variables and are consumed only by the vendor fallbacks -
 * emmcboot, norboot, showlogo - which the distroboot patch puts after
 * distro_bootcmd, and which never run because /boot.scr is found first.
 * Armbian does not use this partitioning at all: it writes a complete MBR disk
 * image to the eMMC starting at offset 0, so /boot is FAT partition 1 and root
 * is ext4 partition 2. ROOTFS_DEV reflects that real layout rather than the
 * vendor's fourth partition, on the principle that a value which is wrong is
 * worse than one that is merely unused; root= comes from armbianEnv.txt as a
 * UUID either way.
 */

#ifndef CVIPART_H
#define CVIPART_H
#ifndef CONFIG_ENV_IS_NOWHERE
#define CONFIG_ENV_IS_NOWHERE
#endif
#define CONFIG_ENV_SIZE 0x20000
#define PART_LAYOUT ""
#define ROOTFS_DEV "/dev/mmcblk0p2"
#define PARTS_OFFSET \
"BOOT_PART_OFFSET=0x0\0" \
"BOOT_PART_SIZE=0x4000\0" \
"MISC_PART_OFFSET=0x4000\0" \
"MISC_PART_SIZE=0x1000\0" \
"ENV_PART_OFFSET=0x5000\0" \
"ENV_PART_SIZE=0x100\0" \
"ROOTFS_PART_OFFSET=0x5100\0" \
"ROOTFS_PART_SIZE=0x1800c0\0"
#define SPL_BOOT_PART_OFFSET 0x0
#endif
