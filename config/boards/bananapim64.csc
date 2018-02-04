# A64 quad core 2GB SoC GBE WiFi eMMC
BOARD_NAME="Banana Pi M64"
BOARDFAMILY="sun50iw1"
BOOTCONFIG_DEFAULT="sun50iw1p1_config"
BOOTCONFIG="bananapi_m64_defconfig"
#
MODULES="bcmdhd"
MODULES_NEXT=""
CPUMIN="408000"
CPUMAX="1296000"
#
KERNEL_TARGET="default,next,dev"
CLI_TARGET=""
DESKTOP_TARGET=""

CLI_BETA_TARGET=""
DESKTOP_BETA_TARGET=""
#
RECOMMENDED="Ubuntu_xenial_dev_nightly:33"
#
BOARDRATING=""
CHIP="https://docs.armbian.com/Hardware_Allwinner-H5-A64/"
HARDWARE="https://linux-sunxi.org/Sinovoip_Banana_Pi_M64"
FORUMS="https://forum.armbian.com/index.php/forum/11-other-boards/"
