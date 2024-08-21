# Rockchip RK3399 hexa core 1-4GB SoC GBe eMMC USB3 WiFi/BT PoE miniDP USB host
BOARD_NAME="Rockpi 4C+"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER=""
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"

BOOTBRANCH_BOARD="tag:v2024.01"
BOOTPATCHDIR="v2024.01"
BOOTCONFIG="rock-4c-plus-rk3399_defconfig"
BOOT_SCENARIO="spl-blobs"
BOOT_SUPPORT_SPI=yes

DDR_BLOB="rk33/rk3399_ddr_933MHz_v1.30.bin"
BL31_BLOB="rk33/rk3399_bl31_v1.36.elf"

function post_family_config___mainline_uboot() {
	declare -g UBOOT_TARGET_MAP="ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB} BL31=$RKBIN_DIR/$BL31_BLOB spl/u-boot-spl u-boot.bin flash.bin;;idbloader.img u-boot.itb"
}
