# Rockchip RK3566 quad core 4/8GB RAM SoC WIFI/BT eMMC USB2 USB3 NVMe PCIe GbE HDMI SPI
BOARD_NAME="Luckfox Core3566"
BOARD_VENDOR="luckfox"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER=""
BOOTCONFIG="luckfox-core3566-rk3566_defconfig"
KERNEL_TARGET="vendor"
KERNEL_TEST_TARGET="vendor"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3566-luckfox-core3566.dtb"
IMAGE_PARTITION_TABLE="gpt"
BOOT_SCENARIO="spl-blobs"
BOOTFS_TYPE="fat" # Only for vendor/legacy
BOOT_SUPPORT_SPI="yes"
BOOT_SPI_RKSPI_LOADER="yes"
MODULES_BLACKLIST_LEGACY="bcmdhd"

# Override family config for this board; let's avoid conditionals in family config.
function post_family_config__luckfox-core3566_use_vendor_uboot() {
	BOOTSOURCE='https://github.com/radxa/u-boot.git'
	BOOTBRANCH='branch:rk35xx-2024.01'
	BOOTPATCHDIR="u-boot-luckfox"

	UBOOT_TARGET_MAP="BL31=$RKBIN_DIR/$BL31_BLOB ROCKCHIP_TPL=$RKBIN_DIR/$DDR_BLOB;;u-boot-rockchip.bin"

	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	function write_uboot_platform() {
		dd if=$1/u-boot-rockchip.bin of=$2 seek=64 conv=notrunc status=none
	}
}
