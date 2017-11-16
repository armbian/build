# A20 dual core 1Gb SoC
BOARD_NAME="SOM-A20"
LINUXFAMILY="sun7i"
BOOTCONFIG="A20-Olimex-SOM-EVB_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp bonding spi_sun7i 8021q a20_tp sun4i_csi0"
MODULES_NEXT="bonding"
#
KERNEL_TARGET="default,next,dev"
CLI_TARGET="jessie,xenial:next"
DESKTOP_TARGET="xenial:default,next"

CLI_BETA_TARGET=""
DESKTOP_BETA_TARGET=""
#
RECOMMENDED="Ubuntu_xenial_default_desktop:90,Debian_jessie_next:100"
#
BOARDRATING=""
CHIP="http://docs.armbian.com/Hardware_Allwinner-A20/"
HARDWARE="https://www.olimex.com/Products/SOM/A20/A20-SOM-EVB/open-source-hardware"
FORUMS="http://forum.armbian.com/index.php/forum/7-allwinner-a10a20/"
