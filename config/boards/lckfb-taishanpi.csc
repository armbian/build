# Rockchip RK3566 quad core 1GB-2GB GBE eMMC USB3 WiFi
BOARD_NAME="LCKFB Taishan Pi"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER=""
BOOTCONFIG="radxa-zero3-rk3566_defconfig"
KERNEL_TARGET="vendor"
BOOT_FDT_FILE="rockchip/rk3566-taishanpi-v10.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"

# Override family config for this board; let's avoid conditionals in family config.
function post_family_config__tspi_use_radxa_vendor() {
	BOOTSOURCE='https://github.com/radxa/u-boot.git'
	BOOTBRANCH='branch:rk35xx-2024.01'
	BOOTPATCHDIR="u-boot-radxa-latest"
	UBOOT_TARGET_MAP="BL31=$RKBIN_DIR/$BL31_BLOB ROCKCHIP_TPL=$RKBIN_DIR/$DDR_BLOB;;u-boot-rockchip.bin"
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd
	function write_uboot_platform() {
		dd if=$1/u-boot-rockchip.bin of=$2 seek=64 conv=notrunc status=none
	}
}
