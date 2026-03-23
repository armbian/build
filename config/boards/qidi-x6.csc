# Rockchip RK3328 quad core 1GB RAM, 1x100M Ethernet, eMMC, USB3, USB2
# Supported boards:
# - QIDI X-6, X-7 (made by Makerbase for 'X-Plus 3', 'X-Smart 3', 'X-Max 3', 'Plus 4' and 'Q1' 3D printers)
#
# These boards and related configuration is very close to Renegade board ("roc-cc-rk3328_defconfig" and "rk3328-roc-cc" DT)
BOARD_NAME="Qidi-x6"
BOARD_VENDOR="makerbase"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER="Shadowrom2020"
BOOTCONFIG="qidi-x6-rk3328_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
HAS_VIDEO_OUTPUT="no"
BOOT_LOGO="none"
MODULES="ads7846 spidev"
BOOTFS_TYPE="fat"
PACKAGE_LIST_BOARD="build-essential usb-modeswitch eject"

enable_extension "brostrend-aic8800-dkms"
