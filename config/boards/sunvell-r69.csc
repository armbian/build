# H2+ quad core 1GB SoC WiFi eMMC
BOARD_NAME="Sunvell R69"
BOARDFAMILY="sun8i"
BOOTCONFIG="sunvell_r69_defconfig"
#
MODULES="xradio_wlan xradio_wlan"
MODULES_NEXT=""
MODULES_BLACKLIST="dhd"
DEFAULT_OVERLAYS="cir analog-codec"
#
KERNEL_TARGET="default,next,dev"
CLI_TARGET="stretch,xenial:next"
DESKTOP_TARGET="stretch:next"
#
CLI_BETA_TARGET=""
DESKTOP_BETA_TARGET=""
