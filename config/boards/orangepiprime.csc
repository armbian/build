# Allwinner H5 quad core 2GB RAM Wi-Fi/BT
BOARD_NAME="Orange Pi Prime"
BOARD_VENDOR="xunlong"
BOARDFAMILY="sun50iw2"
BOARD_MAINTAINER=""
BOOTCONFIG="orangepi_prime_defconfig"
DEFAULT_OVERLAYS="analog-codec"
KERNEL_TARGET="current,edge,legacy"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
CRUSTCONFIG="orangepi_pc2_defconfig"

function post_config_uboot_target__extra_configs_for_orangepi_prime() {
	display_alert "$BOARD" "set dram clock" "info"
	run_host_command_logged scripts/config --set-val CONFIG_DRAM_CLK "504"
	run_host_command_logged scripts/config --enable CONFIG_DRAM_ODT_EN
}
