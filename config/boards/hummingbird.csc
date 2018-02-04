# A20 dual core 1Gb SoC Wifi
BOARD_NAME="Merrii Hummingbird"
BOARDFAMILY="sun7i"
BOOTCONFIG="Merrii_Hummingbird_A20_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i ap6210"
MODULES_NEXT="brcmfmac rfcomm hidp bonding"
#
KERNEL_TARGET="default,next,dev"
CLI_TARGET=""
DESKTOP_TARGET=""

CLI_BETA_TARGET=""
DESKTOP_BETA_TARGET=""
#
BOARDRATING=""
CHIP="http://docs.armbian.com/Hardware_Allwinner-A20/"
HARDWARE="https://linux-sunxi.org/Merrii_Hummingbird_A20"
FORUMS="http://forum.armbian.com/index.php/forum/7-allwinner-a10a20/"
