# Rockchip RK3566 quad core 1GB-2GB GBE eMMC USB3 WiFi
BOARD_NAME="LCKFB Taishan Pi"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER=""
BOOTCONFIG="lckfb-tspi-rk3566_defconfig"
BOOT_SOC="rk3566"
KERNEL_TARGET="vendor,current,edge"
KERNEL_TEST_TARGET="current,vendor"
BOOT_FDT_FILE="rockchip/rk3566-lckfb-tspi.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"

# Override family config for this board; let's avoid conditionals in family config.
function post_family_config__tspi_use_radxa_vendor() {
	display_alert "$BOARD" "Mainline U-Boot overrides for $BOARD - $BRANCH" "info"
	BOOTDELAY=1
	BOOTSOURCE="https://github.com/u-boot/u-boot"
	BOOTBRANCH="tag:v2025.04"
	BOOTPATCHDIR="v2025.04"
	BOOTDIR="u-boot-${BOARD}" # do not share u-boot directory
	UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin u-boot-rockchip-spi.bin"
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd # disable stuff from rockchip64_common; we're using binman here which does all the work already

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}
