# A20 dual core 1Gb SoC Wifi
BOARD_NAME="Merrii Hummingbird"
BOARDFAMILY="sun7i"
BOOTCONFIG="Merrii_Hummingbird_A20_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i ap6210"
MODULES_NEXT="brcmfmac rfcomm hidp bonding"
KERNEL_TARGET="default,next,dev"
