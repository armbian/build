# Rockchip RK3399 hexa core 1-4GB SoC GBe eMMC USB3 WiFi/BT PoE miniDP USB host
BOARD_NAME="Rockpi 4C+"
BOARD_VENDOR="radxa"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER=""
INTRODUCED="2020"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"

BOOTCONFIG="rock-4c-plus-rk3399_defconfig"
BOOT_SUPPORT_SPI=yes

source "${SRC}/config/sources/vendors/radxa/rk3399-uboot.conf.sh"
