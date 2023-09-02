# Rockchip RK3566 quad core 4GB RAM SoC WIFI/BT eMMC USB2
BOARD_NAME="orangepi3b"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER=""
BOOTCONFIG="orangepi-3b-rk3566_defconfig"
KERNEL_TARGET="legacy,edge"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3566-orangepi-3b.dtb"
IMAGE_PARTITION_TABLE="gpt"
BOOT_SCENARIO="spl-blobs"
BOOT_SUPPORT_SPI="yes"
BOOT_SPI_RKSPI_LOADER="yes"
MODULES="sprdbt_tty sprdwl_ng"
MODULES_BLACKLIST_LEGACY="bcmdhd"

# Override family config for this board; let's avoid conditionals in family config.
function post_family_config__orangepi3b_use_vendor_uboot() {
	BOOTSOURCE='https://github.com/orangepi-xunlong/u-boot-orangepi.git'
	BOOTBRANCH='branch:v2017.09-rk3588'
	BOOTPATCHDIR="legacy"
}
