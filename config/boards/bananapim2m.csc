 # R16(A33) quad core 512MB SoC
BOARD_NAME="Banana PI BPI-M2 Magic"
BOARDFAMILY="sun8i"

BOOTCONFIG="Bananapi_m2m_defconfig"
# ./build/cache/sources/u-boot/v2018.05/config/Bananapi_m2m_defconfig

MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i 8021q a20_tp"
MODULES_NEXT=""
OVERLAY_PREFIX="sun8i-a33"
#
KERNEL_TARGET="next,dev"
CLI_TARGET="stretch,bionic:next"
DESKTOP_TARGET=""
#
CLI_BETA_TARGET=""
