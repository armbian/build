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

