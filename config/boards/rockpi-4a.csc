# Rockchip RK3399 hexa core 1-4GB SoC GBe eMMC USB3
BOARD_NAME="Rockpi 4A"
BOARD_VENDOR="radxa"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER=""
INTRODUCED="2019"
BOOTBRANCH_BOARD="tag:v2026.07"
BOOTPATCHDIR="v2026.07"
BOOTCONFIG="rock-pi-4-rk3399_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3399-rock-pi-4a.dtb"
BOOT_SCENARIO="binman-atf-mainline"
BOOT_SUPPORT_SPI=yes
enable_extension "uboot-btrfs"

# v2026.07 rock-pi-4-rk3399_defconfig sets CONFIG_SYS_SPI_U_BOOT_OFFS=0xE0000, while the
# generic rockchip64 rkspi_loader.img places u-boot.itb at 0x60000 — SPL would never find
# the FIT. Ship binman's ready-made SPI image instead and skip the generic SPI postprocess;
# family write_uboot_platform/_mtd already handle u-boot-rockchip[-spi].bin.
function post_family_config__rockpi4a_binman_spi_image() {
	display_alert "$BOARD" "u-boot: package binman SPI image (u-boot-rockchip-spi.bin)" "info"
	declare -g UBOOT_TARGET_MAP="BL31=bl31.elf ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin u-boot-rockchip-spi.bin"
	unset uboot_custom_postprocess
}
