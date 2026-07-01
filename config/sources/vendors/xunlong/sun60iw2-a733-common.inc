# Shared configuration for the Xunlong Orange Pi A733 (sun60iw2) boards.
BOARD_VENDOR="xunlong"
BOARDFAMILY="sun60iw2"
KERNEL_TARGET="vendor"
KERNEL_TEST_TARGET="vendor"
IMAGE_PARTITION_TABLE="msdos"
OVERLAY_PREFIX="sun60i-a733"
KERNELPATCHDIR="archive/sun60iw2-opi-vendor"

# In-tree boot blobs consumed by the family's uboot_custom_postprocess; sys_config is shared.
declare -g SUNXI_SYS_CONFIG_FEX="${SRC}/packages/blobs/sunxi/sun60iw2/sys_config_orangepi.fex"

# Invalidate U-Boot cache if any of the blobs change
UBOOT_HASH_EXTRA="$(cat "${SUNXI_BOOT0_SDCARD_FEX}" "${SUNXI_BOOT0_SPINOR_FEX}" "${SUNXI_SYS_CONFIG_FEX}" | sha256sum | cut -d' ' -f1)"

function write_uboot_platform() {
	local SCRIPT_DIR="$1" DEVICE="$2"
	dd conv=notrunc,fsync status=none if="${SCRIPT_DIR}/boot0_sdcard.fex" of="${DEVICE}" bs=1k seek=8
	dd conv=notrunc,fsync status=none if="${SCRIPT_DIR}/boot_package.fex" of="${DEVICE}" bs=1k seek=16400
	sync "${DEVICE}"
}
