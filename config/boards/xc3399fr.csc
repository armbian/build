# Rockchip RK3399 hexa core 4GB LPDDR4 eMMC GBE 2x USB3 HDMI WiFi/BT
BOARD_NAME="XC3399FR"
BOARD_VENDOR="proembed"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER="liamhnam"
INTRODUCED="2021"
BOOTCONFIG="fine3399-rk3399_defconfig"
KERNEL_TARGET="current,edge,bleedingedge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3399-xc3399fr.dtb"
BOOT_SCENARIO="only-blobs"

# Deliberately no SRC_EXTLINUX here, unlike fine3399 which this device tree was
# derived from. boot.scr + armbianEnv.txt is what makes the stock
# armbian-install "boot from eMMC, system on this disk" flow work on this
# board: the rockchip64 boot script resolves every path through ${prefix}, so
# one script boots whether /boot is a directory (SD) or its own partition
# (eMMC). Worth revisiting once armbian/configng#985 is merged.
