# Rockchip RK3328 quad core 1GB RAM, 1x100M Ethernet, eMMC, USB3, USB2
# Supported boards:
#
# - MKS-KLIPAD50
#
# (There is no dedicated source code archive for this board, but it is
# very similar to https://github.com/makerbase-mks/MKS-PI
# and https://github.com/makerbase-mks/MKS-SKIPR.)
#
# These boards and related configuration is very close to Renegade board ("roc-cc-rk3328_defconfig" and "rk3328-roc-cc" DT).
# The mksklipad50 is same as mkspi, but with a different devicetree file.
BOARD_NAME="mksklipad50"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER="torte71"
BOOTCONFIG="mksklipad50-rk3328_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
MODULES="pinctrl-rk805 ads7846 spidev"
BOOTFS_TYPE="fat"
PACKAGE_LIST_BOARD="build-essential usb-modeswitch"
