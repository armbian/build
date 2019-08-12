# A13 single core 512Mb
BOARD_NAME="A13-OLinuXino"
BOARDFAMILY="sun5i"
BOOTCONFIG="A13-OLinuXino_defconfig"
#
MODULES="gpio_sunxi spi_sunxi 8021q 8192cu 8188eu sun4i_ts"
MODULES_NEXT="bonding"
#
KERNEL_TARGET="next,dev"
