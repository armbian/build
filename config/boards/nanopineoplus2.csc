# Allwinner H5 quad core 1GB RAM SoC headless GBE eMMC WiFi/BT
BOARD_NAME="NanoPi Neo Plus 2"
BOARDFAMILY="sun50iw2"
BOARD_MAINTAINER="teknoid"
BOOTCONFIG="nanopi_neo_plus2_defconfig"
MODULES="g_serial"
MODULES_BLACKLIST="lima"
DEFAULT_OVERLAYS="usbhost1 usbhost2"
DEFAULT_CONSOLE="serial"
SERIALCON="ttyS0,ttyGS0"
HAS_VIDEO_OUTPUT="no"
KERNEL_TARGET="legacy,current,edge"
KERNEL_TEST_TARGET="current"
CRUSTCONFIG="h5_defconfig"

function post_config_uboot_target__extra_configs_for_nanopi_neo_plus2() {
	display_alert "$BOARD" "set dram clock" "info"
	run_host_command_logged scripts/config --set-val CONFIG_DRAM_CLK "504"
}
