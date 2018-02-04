# A20 dual core 1Gb SoC
BOARD_NAME="Banana Pi M1+"
BOARDFAMILY="sun7i"
BOOTCONFIG="bananapi_m1_plus_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sun7i 8021q a20_tp #ap6211"
MODULES_NEXT="brcmfmac bonding"
#
KERNEL_TARGET="default,next,dev"
CLI_TARGET=""
DESKTOP_TARGET=""
#
CLI_BETA_TARGET=""
DESKTOP_BETA_TARGET=""
#

#
BOARDRATING=""
CHIP="http://docs.armbian.com/Hardware_Allwinner-A20/"
HARDWARE="https://linux-sunxi.org/Banana_Pi"
FORUMS="http://forum.armbian.com/index.php/forum/7-allwinner-a10a20/"
