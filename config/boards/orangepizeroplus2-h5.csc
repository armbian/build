# Allwinner H5 quad core 512MB RAM SoC Wi-Fi/BT
BOARD_NAME="Orange Pi Zero Plus 2"
BOARDFAMILY="sun50iw2"
BOARD_MAINTAINER=""
BOOTCONFIG="orangepi_zero_plus2_defconfig"
MODULES_LEGACY="g_serial"
MODULES_CURRENT="g_serial"
DEFAULT_OVERLAYS="gpio-regulator-1.3v usbhost2 usbhost3"
HAS_VIDEO_OUTPUT="no"
SERIALCON="ttyS0,ttyGS0"
KERNEL_TARGET="legacy,current,edge"
KERNEL_TEST_TARGET="current"
CRUSTCONFIG="h5_defconfig"

function post_config_uboot_target__extra_configs_for_orangepi_zero_plus2() {
	display_alert "$BOARD" "set dram clock" "info"
	run_host_command_logged scripts/config --set-val CONFIG_DRAM_CLK "504"
}
