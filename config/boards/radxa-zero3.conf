# Rockchip RK3566 quad core
BOARD_NAME="Radxa ZERO 3"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER="Radxa"
BOOTCONFIG="radxa-zero3-rk3566_defconfig"
KERNEL_TARGET="vendor,edge"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3566-radxa-zero3.dtb"
IMAGE_PARTITION_TABLE="gpt"
BOOT_SCENARIO="spl-blobs"
BOOTFS_TYPE="fat" # Only for vendor/legacy

function post_family_config_branch_edge__use_mainline_dtb_name() {
	unset BOOT_FDT_FILE # boot.scr will use whatever u-boot detects and sets 'fdtfile' to
	unset BOOTFS_TYPE   # mainline u-boot can boot ext4 directly
}

# Override family config for this board; let's avoid conditionals in family config.
function post_family_config__radxa-zero3_use_vendor_uboot() {
	BOOTSOURCE='https://github.com/radxa/u-boot.git'
	BOOTBRANCH='branch:rk35xx-2024.01'
	BOOTPATCHDIR="u-boot-radxa-latest"

	UBOOT_TARGET_MAP="BL31=$RKBIN_DIR/$BL31_BLOB ROCKCHIP_TPL=$RKBIN_DIR/$DDR_BLOB;;u-boot-rockchip.bin"

	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	function write_uboot_platform() {
		dd if=$1/u-boot-rockchip.bin of=$2 seek=64 conv=notrunc status=none
	}
}

function post_family_config_branch_edge__radxa-zero3_use_kwiboo_uboot() {
	BOOTCONFIG="radxa-zero-3-rk3566_defconfig"
	BOOTSOURCE='https://github.com/Kwiboo/u-boot-rockchip.git'
	BOOTBRANCH='branch:rk3xxx-2024.07'
	BOOTPATCHDIR="u-boot-zero3" # Empty

	UBOOT_TARGET_MAP="BL31=$RKBIN_DIR/$BL31_BLOB ROCKCHIP_TPL=$RKBIN_DIR/$DDR_BLOB;;u-boot-rockchip.bin"

	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	function write_uboot_platform() {
		dd if=$1/u-boot-rockchip.bin of=$2 seek=64 conv=notrunc status=none
	}
}
