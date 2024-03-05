# Rockchip RK3528 quad core 1-8GB SoC GBe eMMC USB3 Wifi Bt
BOARD_NAME="HinLink HT2"
BOARDFAMILY="rk35xx"
BOOTCONFIG="hinlink_rk3528_defconfig"
BOARD_MAINTAINER="hoochiwetech"
KERNEL_TARGET="legacy,vendor"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3528-hinlink-ht2.dtb"
BOOT_SCENARIO="spl-blobs"
WIREGUARD="no"
IMAGE_PARTITION_TABLE="gpt"
BOOTFS_TYPE="ext4"

# Override family config for this board; let's avoid conditionals in family config.
function post_family_config__hinlink-h28k_use_vendor_uboot() {
	BOOTSOURCE='https://github.com/rockchip-linux/u-boot.git'
	BOOTBRANCH='commit:32640b0ada9344f91e7a407576568782907161cd'
	BOOTPATCHDIR="legacy/board_hinlink-h28k"
}
