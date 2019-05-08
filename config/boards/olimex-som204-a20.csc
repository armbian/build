# A20 dual core 1Gb SoC dual ethernet
BOARD_NAME="SOM204-A20"
BOARDFAMILY="sun7i"
BOOTCONFIG="A20-Olimex-SOM204-EVB-eMMC_defconfig"
MODULES="8021q a20_tp bonding ft5x_ts g_serial gpio_sunxi m25p80 spi_sun7i sunxi_lirc_new sunxi_can"
MODULES_NEXT="bonding g_serial gpio-ir-tx r8723bs"
MODULES_DEV="bonding g_serial gpio-ir-tx r8723bs "
#
KERNEL_TARGET="default,next,dev"
CLI_TARGET="stretch,xenial:next"
DESKTOP_TARGET="xenial:default,next"
#
CLI_BETA_TARGET=""
DESKTOP_BETA_TARGET=""
