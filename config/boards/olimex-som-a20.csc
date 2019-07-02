# A20 dual core 1Gb SoC
BOARD_NAME="SOM-A20"
BOARDFAMILY="sun7i"
BOOTCONFIG="A20-Olimex-SOM-EVB_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i 8021q a20_tp sun4i_csi0"
MODULES_NEXT="bonding"
#
KERNEL_TARGET="default,next,dev"
CLI_TARGET="buster,xenial:next"
DESKTOP_TARGET="xenial:default,next"
CLI_BETA_TARGET=""
DESKTOP_BETA_TARGET=""
