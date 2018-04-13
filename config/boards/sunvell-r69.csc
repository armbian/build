# H2+ quad core 1GB SoC WiFi eMMC
BOARD_NAME="Sunvell R69"
BOARDFAMILY="sun8i"
BOOTCONFIG="sunvell_r69_defconfig"
#
MODULES="xradio_wlan xradio_wlan"
MODULES_NEXT=""
MODULES_BLACKLIST="dhd"
DEFAULT_OVERLAYS="cir analog-codec"
CPUMIN=240000
CPUMAX=1008000
#
KERNEL_TARGET="default,next,dev"
CLI_TARGET="stretch,xenial:next"
DESKTOP_TARGET="stretch:next"
#
CLI_BETA_TARGET=""
DESKTOP_BETA_TARGET=""
#
BOARDRATING=""
CHIP="http://docs.armbian.com/Hardware_Allwinner-H3/"
HARDWARE="http://linux-sunxi.org/Sunvell_R69"
FORUMS="http://forum.armbian.com/index.php/forum/13-allwinner-h3/"

