# Rockchip RK3576 octa core SoC GBe eMMC microSD USB3 PCIe HDMI DP
BOARD_NAME="LubanCat 3 v2"
BOARD_VENDOR="embedfire"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER=""
INTRODUCED="2026"
BOOTCONFIG="lubancat-3-v2-rk3576_defconfig"
BOOT_SOC="rk3576"
SERIALCON="ttyS0"
KERNEL_TARGET="vendor,current,edge,bleedingedge"
KERNEL_TEST_TARGET="vendor,current"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3576-lubancat-3-v2.dtb"
BOOT_SCENARIO="binman"
IMAGE_PARTITION_TABLE="gpt"

function post_family_config__lubancat_3_v2_use_mainline_uboot() {
	declare -g BOOTDELAY=1
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2026.07"
	declare -g BOOTPATCHDIR="v2026.07"
	declare -g BOOTDIR="u-boot-${BOARD}"
	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"

	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}
