# Allwinner A733 octa core 2-16GB RAM GBE USB3 WiFi/BT NVMe eMMC
BOARD_NAME="Orange Pi 4 Pro"
BOARD_VENDOR="xunlong"
BOARDFAMILY="sun60iw2"
BOARD_MAINTAINER="shkolnik"
INTRODUCED="2025"
KERNEL_TARGET="vendor,edge"
KERNEL_TEST_TARGET="vendor,edge"
IMAGE_PARTITION_TABLE="msdos"
HAS_VIDEO_OUTPUT="no" # no desktop on this vendor kernel; board-level so the build-list inventory sees it

BOOTCONFIG_VENDOR="sun60iw2p1_t736_defconfig"
BOOTCONFIG_EDGE="orangepi_4_pro_defconfig"

BOOT_FDT_FILE="allwinner/sun60i-a733-orangepi-4-pro.dtb"
SUNXI_BOOT0_SDCARD_FEX="${SRC}/packages/blobs/sunxi/sun60iw2/boot0_sdcard_orangepi4pro.fex"
SUNXI_BOOT0_SPINOR_FEX="${SRC}/packages/blobs/sunxi/sun60iw2/boot0_spinor_orangepi4pro.fex"
SUNXI_SYS_CONFIG_FEX="${SRC}/packages/blobs/sunxi/sun60iw2/sys_config_orangepi.fex"

# Packages needed for hardware enablement and flashing
PACKAGE_LIST_BOARD="mtd-utils"


# Invalidate U-Boot cache if any of the blobs change
UBOOT_HASH_EXTRA="$(cat "${SUNXI_BOOT0_SDCARD_FEX}" "${SUNXI_BOOT0_SPINOR_FEX}" "${SUNXI_SYS_CONFIG_FEX}" | sha256sum | cut -d' ' -f1)"

# The 4 Pro has 16 MB SPI-NOR; support writing the bootloader to MTD
function write_uboot_platform_mtd() {
	local SCRIPT_DIR="$1"
	[[ -f "${SCRIPT_DIR}/boot0_spinor.fex" ]] || SCRIPT_DIR="/usr/lib/linux-u-boot-edge-orangepi4pro"
	[[ -f "${SCRIPT_DIR}/boot0_spinor.fex" ]] || SCRIPT_DIR="${DIR}"
	local TARGET_DEV="${2:-/dev/mtd0}"
	# Ensure character MTD device (/dev/mtd0) even if block device (/dev/mtdblock0) was passed
	local MTD_DEV="${TARGET_DEV/mtdblock/mtd}"
	[[ -c "${MTD_DEV}" ]] || MTD_DEV="/dev/mtd0"
	[[ -c "${MTD_DEV}" ]] || { echo "write_uboot_platform_mtd: MTD device ${MTD_DEV} not found" >&2; return 1; }

	local BOOT0="${SCRIPT_DIR}/boot0_spinor.fex"
	local BOOTPKG="${SCRIPT_DIR}/boot_package.fex"

	[[ -f "${BOOT0}" ]] || { echo "write_uboot_platform_mtd: ${BOOT0} not found" >&2; return 1; }
	[[ -f "${BOOTPKG}" ]] || { echo "write_uboot_platform_mtd: ${BOOTPKG} not found" >&2; return 1; }

	local SIZE_BOOT0; SIZE_BOOT0="$(stat -c%s "${BOOT0}")"
	local SIZE_BOOTPKG; SIZE_BOOTPKG="$(stat -c%s "${BOOTPKG}")"

	echo "Erasing MTD device ${MTD_DEV} (4MB for bootloader)..."
	flash_erase "${MTD_DEV}" 0 1024 || { echo "write_uboot_platform_mtd: flash_erase failed on ${MTD_DEV}" >&2; return 1; }

	echo "Writing ${BOOT0} (${SIZE_BOOT0} bytes) to ${MTD_DEV} @ 0..."
	mtd_debug write "${MTD_DEV}" 0 "${SIZE_BOOT0}" "${BOOT0}" ||
		{ echo "write_uboot_platform_mtd: writing ${BOOT0} failed" >&2; return 1; }

	echo "Writing ${BOOTPKG} (${SIZE_BOOTPKG} bytes) to ${MTD_DEV} @ 262144 (256KB)..."
	mtd_debug write "${MTD_DEV}" 262144 "${SIZE_BOOTPKG}" "${BOOTPKG}" ||
		{ echo "write_uboot_platform_mtd: writing ${BOOTPKG} failed" >&2; return 1; }

	sync
	echo "write_uboot_platform_mtd: successfully flashed SPI NOR bootloader to ${MTD_DEV}"
	return 0
}

