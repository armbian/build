# Xiangcheng XC3399FR - RK3399 hexa core 4GB LPDDR4, GbE, eMMC, 2x USB3, HDMI, WiFi/BT
BOARD_NAME="XC3399FR"
BOARD_VENDOR="proembed"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER="liamhnam"
BOOTCONFIG="fine3399-rk3399_defconfig"
KERNEL_TARGET="current"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3399-xc3399fr.dtb"
BOOT_SCENARIO="only-blobs"

# This board is intentionally NOT configured with SRC_EXTLINUX="yes" (unlike
# fine3399, which the device tree was derived from). Using boot.scr +
# armbianEnv.txt is what lets the stock armbian-install "boot from eMMC, system
# on this disk" flow work: the rockchip64 boot script resolves every path
# through ${prefix}, so a single script boots whether /boot is a directory (SD)
# or its own partition (eMMC), whereas extlinux.conf's absolute paths break the
# eMMC layout and armbian-install has no extlinux support.
