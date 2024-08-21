# Rockchip RK3568 quad core 2GB-4GB 5GBE eMMC SATA USB3 Mini PCIE M.2 key-e
BOARD_NAME="Banana Pi R2 Pro"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER=""
BOOTCONFIG="bpi-r2-pro-rk3568_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3568-bpi-r2-pro.dtb"
BOOTBRANCH_BOARD="tag:v2024.01"
BOOTPATCHDIR="v2024.01"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyS02,1500000 console=tty0"
ASOUND_STATE="asound.state.station-p2"
IMAGE_PARTITION_TABLE="gpt"

function post_family_config___mainline_uboot() {
	declare -g UBOOT_TARGET_MAP="ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB} BL31=$RKBIN_DIR/$BL31_BLOB spl/u-boot-spl u-boot.bin flash.bin;;idbloader.img u-boot.itb"
}
