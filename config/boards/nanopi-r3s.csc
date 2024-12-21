# Rockchip RK3566 quad core, dual GBe NIC
BOARD_NAME="FriendlyElec NanoPi R3S"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER=""
BOOTCONFIG="nanopi-r3s-rk3566_defconfig"
KERNEL_TARGET="edge"
#KERNEL_TEST_TARGET="edge"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3566-nanopi-r3s.dtb"
IMAGE_PARTITION_TABLE="gpt"
BOOT_SCENARIO="spl-blobs"
BOOTFS_TYPE="fat" # Only for vendor/legacy

function post_family_config_branch_edge__use_mainline_dtb_name() {
	unset BOOT_FDT_FILE # boot.scr will use whatever u-boot detects and sets 'fdtfile' to
	unset BOOTFS_TYPE   # mainline u-boot can boot ext4 directly
}

# Override family config for this board; let's avoid conditionals in family config.
# vendor support not there yet
function post_family_config__nanopi-r3s_use_vendor_uboot() {
	BOOTSOURCE='https://github.com/radxa/u-boot.git'
	BOOTBRANCH='branch:rk35xx-2024.01'
	BOOTPATCHDIR="u-boot-radxa-latest"

	UBOOT_TARGET_MAP="BL31=$RKBIN_DIR/$BL31_BLOB ROCKCHIP_TPL=$RKBIN_DIR/$DDR_BLOB;;u-boot-rockchip.bin"

	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	function write_uboot_platform() {
		dd if=$1/u-boot-rockchip.bin of=$2 seek=64 conv=notrunc status=none
	}
}

function post_family_config_branch_edge__nanopi-r3s_use_mainline_uboot() {
	BOOTCONFIG="nanopi-r3s-rk3566_defconfig"
	BOOTSOURCE="https://github.com/u-boot/u-boot"
	BOOTBRANCH="tag:v2024.10"
	BOOTPATCHDIR="v2024.10"

	UBOOT_TARGET_MAP="BL31=$RKBIN_DIR/$BL31_BLOB ROCKCHIP_TPL=$RKBIN_DIR/$DDR_BLOB;;u-boot-rockchip.bin"

	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	function write_uboot_platform() {
		dd if=$1/u-boot-rockchip.bin of=$2 seek=64 conv=notrunc status=none
	}
}
