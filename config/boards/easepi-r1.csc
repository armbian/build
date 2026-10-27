# Rockchip RK3568 quad core SoC 2/4GB LPDDR4 16GB eMMC m.2 2x1G 2x2.5G USB3 HDMI
BOARD_NAME="EasePi-R1"
BOARD_VENDOR="linkease"
BOARDFAMILY="rk35xx"
OVERLAY_PREFIX="rockchip-rk3568"
BOARD_MAINTAINER="kunxiang1"
INTRODUCED="2025"
BOOTCONFIG="easepi-r1-rk3568_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3568-easepi-r1.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"
BOOTFS_TYPE="fat"

function post_family_config__easepi_r1_use_mainline_uboot() {
	display_alert "$BOARD" "Using mainline U-Boot (${BOOTCONFIG})" "info"

	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot"
	declare -g BOOTBRANCH="tag:v2026.10"
	declare -g BOOTPATCHDIR="v2026.10"
	declare -g BOOTDIR="u-boot-${BOARD}"
	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}
