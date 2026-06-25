# Rockchip RK3328 quad core 1GB RAM, 1x100M Ethernet, eMMC, USB3, USB2
# Supported boards:
# - QIDI X-6, X-7 (made by Makerbase for 'X-Plus 3', 'X-Smart 3', 'X-Max 3', 'Plus 4' and 'Q1' 3D printers)
#
# These boards and related configuration is very close to Renegade board ("roc-cc-rk3328_defconfig" and "rk3328-roc-cc" DT)
BOARD_NAME="Qidi-x6"
BOARD_VENDOR="makerbase"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER="Shadowrom2020"
INTRODUCED="2025"
BOOTCONFIG="qidi-x6-rk3328_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
HAS_VIDEO_OUTPUT="no"
BOOT_LOGO="none"
MODULES="ads7846 spidev"
BOOTFS_TYPE="fat"
PACKAGE_LIST_BOARD="build-essential usb-modeswitch eject"

enable_extension "brostrend-aic8800-dkms"

function post_family_config__qidi_x6_use_mainline_uboot() {
	display_alert "$BOARD" "Using mainline U-Boot for $BOARD / $BRANCH" "info"

	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2026.04"
	declare -g BOOTPATCHDIR="v2026.04"
	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"

	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}
