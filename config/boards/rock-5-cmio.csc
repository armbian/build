# Rockchip RK3588S octa core 4/8/16GB RAM SoC NVMe USB3 USB-C GbE
BOARD_NAME="Radxa CM5"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER=""
BOOTCONFIG="orangepi_5_defconfig" # vendor name, not standard, see hook below, set BOOT_SOC below to compensate
BOOT_SOC="rk3588"
KERNEL_TARGET="legacy"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3588s-radxa-cm5-io.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"

# HACK HACK HACK, using the opi5 uboot for now
function post_family_config__cm5_use_orangepi5_uboot() {
	BOOTSOURCE='https://github.com/orangepi-xunlong/u-boot-orangepi.git'
	BOOTBRANCH='branch:v2017.09-rk3588'
	BOOTPATCHDIR="legacy"
}
