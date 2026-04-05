# Rockchip RK3566 with 4GB DDR HDMI USB3 WIFI GMAC
BOARD_NAME="RK3566 BOX DEMO"
BOARD_VENDOR="rockchip"
BOOT_SOC="rk3566"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER="andyshrk"
BOOTCONFIG="generic-rk3568_defconfig"
KERNEL_TARGET="current,edge"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3566-box-demo.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"

# Mainline U-Boot
function post_family_config__rk3566_box_demo_use_mainline_uboot() {
	display_alert "$BOARD" "Using mainline U-Boot for $BOARD / $BRANCH" "info"

	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2025.10"
	declare -g BOOTPATCHDIR="v2025.10"
	# Don't set BOOTDIR, allow shared U-Boot source directory for disk space efficiency

	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"

	# Disable stuff from rockchip64_common; we're using binman here which does all the work already
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}
