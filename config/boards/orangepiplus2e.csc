# Allwinner H3 quad core 2GB RAM WiFi GBE eMMC
BOARD_NAME="Orange Pi+ 2E"
BOARD_VENDOR="xunlong"
BOARDFAMILY="sun8i"
BOARD_MAINTAINER=""
BOOTCONFIG="orangepi_plus2e_defconfig"
KERNEL_TARGET="current,edge,legacy"
KERNEL_TEST_TARGET="legacy"
FULL_DESKTOP="yes"

function post_config_uboot_target__extra_configs_for_orangepi_plus2e() {
	display_alert "$BOARD" "set dram clock" "info"
	run_host_command_logged scripts/config --set-val CONFIG_DRAM_CLK "624"
	run_host_command_logged scripts/config --set-val CONFIG_DRAM_ZQ "3881979"
	run_host_command_logged scripts/config --enable CONFIG_DRAM_ODT_EN
}
