# Rockchip RK3566 quad-core ELTAY RM66 compute module
BOARD_NAME="ELTAY RM66"
BOARD_VENDOR="elron"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER="RiPetitor"
INTRODUCED="2026"
BOOTCONFIG="eltay-rm66-rk3566_defconfig"
BOOT_SOC="rk3566"
KERNEL_TARGET="current"
KERNEL_TEST_TARGET="current"
BOOT_FDT_FILE="rockchip/rk3566-eltay-rm66.dtb"
IMAGE_PARTITION_TABLE="gpt"
BOOT_SCENARIO="binman"
BOOT_SUPPORT_SPI="no"

function post_family_config__eltay_rm66_mainline_uboot() {
	[[ "${BRANCH}" == "current" ]] || exit_with_error "Eltay RM66 currently supports BRANCH=current only"

	display_alert "$BOARD" "EXPERIMENTAL: generic DT default; carrier wiring requires validation" "wrn"
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2026.01"
	declare -g BOOTPATCHDIR="v2026.01"
	declare -g BOOTDELAY=1
	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"
}
