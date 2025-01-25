# Rockchip RK3568 quad core 1-8GB SoC GBe eMMC USB3
BOARD_NAME="100ASK DShanPI R1"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER=""
BOOTCONFIG="dshanpi-r1-rk3568_defconfig"
KERNEL_TARGET="vendor"
KERNEL_TEST_TARGET="vendor"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3568-dshapi-r1.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"

function post_family_config__dshanpi-r1_use_mainline_uboot() {
	display_alert "$BOARD" "Mainline U-Boot overrides for $BOARD - $BRANCH" "info"
	unset BOOTFS_TYPE # fixes armbian-install and unneeded for modern uboot anyway
	declare -g BOOTCONFIG="dshanpi-r1-rk3568_defconfig"
	declare -g BOOTDELAY=1
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot"
	declare -g BOOTBRANCH="tag:v2024.10"
	declare -g BOOTPATCHDIR="v2024.10"
	declare -g BOOTDIR="u-boot-${BOARD}" # do not share u-boot directory
	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin u-boot-rockchip-spi.bin"
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd # disable stuff from rockchip64_common; we're using binman here which does all the work already

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}
