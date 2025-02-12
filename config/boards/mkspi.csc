# Rockchip RK3328 quad core 1GB RAM, 1x100M Ethernet, eMMC, USB3, USB2
# Supported boards:
# - MKS-PI - https://github.com/makerbase-mks/MKS-PI
# - MKS-SKIPR - https://github.com/makerbase-mks/MKS-SKIPR
# - QIDI X-4 and X-6 (made by Makerbase for 'X-Plus 3' and 'X-Max 3' 3D printers) - partially supported
#
# These boards and related configuration is very close to Renegade board ("roc-cc-rk3328_defconfig" and "rk3328-roc-cc" DT)
BOARD_NAME="mkspi"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER="redrathnure"
BOOTCONFIG="mkspi-rk3328_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
#No need to build Desktop images, minimal set will be installed together with KlipperScreen
HAS_VIDEO_OUTPUT="no"
BOOT_LOGO="desktop"
MODULES="ads7846 spidev"
BOOTFS_TYPE="fat"
PACKAGE_LIST_BOARD="build-essential usb-modeswitch"
