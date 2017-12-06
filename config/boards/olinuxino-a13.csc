# A13 single core 512Mb
BOARD_NAME="A13-OLinuXino"
BOARDFAMILY="sun5i"
BOOTCONFIG="A13-OLinuXino_defconfig"
#
MODULES="gpio_sunxi spi_sunxi 8021q 8192cu 8188eu sun4i_ts"
MODULES_NEXT="bonding"
#
KERNEL_TARGET="default,next,dev"
CLI_TARGET="jessie,xenial:next"
DESKTOP_TARGET="xenial:default,next"
#
RECOMMENDED="Ubuntu_xenial_default_desktop:90,Debian_jessie_next:100"
#
BOARDRATING=""
CHIP="http://docs.armbian.com/Hardware_Allwinner-A20/"
HARDWARE="https://www.olimex.com/Products/OLinuXino/A13/A13-OLinuXino/open-source-hardware"
FORUMS="http://forum.armbian.com/index.php/forum/7-allwinner-a10a20/"
