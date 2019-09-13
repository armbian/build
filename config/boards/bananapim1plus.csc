# A20 dual core 1Gb SoC GBE WiFi 1xSATA
BOARD_NAME="Banana Pi M1+"
BOARDFAMILY="sun7i"
BOOTCONFIG="bananapi_m1_plus_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i 8021q a20_tp #ap6211"
MODULES_NEXT="brcmfmac bonding"
KERNEL_TARGET="default,next,dev"
