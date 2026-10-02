# Rockchip RK3568 quad core 1-8GB SoC GBe eMMC USB3
BOARD_NAME="100ASK DshanPi R1 / R1+"
BOARD_VENDOR="dongshanpi"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER=""
INTRODUCED="2024"
BOOTCONFIG="dshanpi-r1-rk3568_defconfig"
KERNEL_TARGET="vendor"
KERNEL_TEST_TARGET="vendor"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3568-dshanpi-r1.dtb"
BOOT_SCENARIO="binman"
IMAGE_PARTITION_TABLE="gpt"

function post_family_config__dshanpi-r1_use_mainline_uboot() {
	display_alert "$BOARD" "Mainline U-Boot overrides for $BOARD - $BRANCH" "info"
	declare -g BOOTCONFIG="dshanpi-r1-rk3568_defconfig"
	declare -g BOOTDELAY=1
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot"
	declare -g BOOTBRANCH="tag:v2026.07"
	declare -g BOOTPATCHDIR="v2026.07"
	declare -g BOOTDIR="u-boot-${BOARD}"
}
