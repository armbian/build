# A33 quad core 1Gb SoC
BOARD_NAME="Lime A33"
BOARDFAMILY="sun8i"
BOOTCONFIG="A33-OLinuXino_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i 8021q a20_tp"
MODULES_NEXT=""
OVERLAY_PREFIX="sun8i-a33"
#
KERNEL_TARGET="next,dev"
CLI_TARGET="buster,bionic:next"
DESKTOP_TARGET=""
#
CLI_BETA_TARGET=""
