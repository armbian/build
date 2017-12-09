# H2+ quad core 1GB SoC WiFi eMMC
BOARD_NAME="Sunvell R69"
BOARDFAMILY="sun8i"
BOOTCONFIG="sunvell_r69_defconfig"
#
MODULES="xradio_wlan xradio_wlan"
MODULES_NEXT="xradio_wlan"
MODULES_BLACKLIST="dhd"
CPUMIN=240000
CPUMAX=1104000
#
KERNEL_TARGET="default next"
CLI_TARGET="jessie,xenial:default"

CLI_BETA_TARGET="xenial,stretch:next"
DESKTOP_TARGET="xenial:default"

CLI_BETA_TARGET="jessie:default"
DESKTOP_BETA_TARGET="xenial:default"
