# Rockchip RK3399T hexa core 1-4GB SoC GBe eMMC USB3 WiFi/BT PoE
BOARD_NAME="Rock 4SE"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER=""
BOOTPATCHDIR="v2025.04"
BOOTBRANCH_BOARD="tag:v2025.04"
BOOTCONFIG="rock-4se-rk3399_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3399-rock-4se.dtb"
BOOT_SCENARIO="spl-blobs"
BOOT_SUPPORT_SPI="yes"
BL31_BLOB="rk33/rk3399_bl31_v1.36.elf"
DDR_BLOB="rk33/rk3399_ddr_933MHz_v1.30.bin"

function post_family_config___mainline_uboot() {
	declare -g UBOOT_TARGET_MAP="ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB} BL31=$RKBIN_DIR/$BL31_BLOB spl/u-boot-spl u-boot.bin flash.bin;;idbloader.img u-boot.itb"
}
