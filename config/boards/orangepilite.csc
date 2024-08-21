# Allwinner H3 quad core 512MB RAM WiFi
BOARD_NAME="Orange Pi Lite"
BOARDFAMILY="sun8i"
BOARD_MAINTAINER=""
BOOTCONFIG="orangepi_lite_defconfig"
MODULES_LEGACY="g_serial"
MODULES_CURRENT="g_serial"
KERNEL_TARGET="legacy,current,edge"
KERNEL_TEST_TARGET="current"

function post_config_uboot_target__extra_configs_for_orangepi_lite() {
	display_alert "$BOARD" "set dram clock" "info"
	run_host_command_logged scripts/config --set-val CONFIG_DRAM_CLK "624"
	run_host_command_logged scripts/config --set-val CONFIG_DRAM_ZQ "3881979"
	run_host_command_logged scripts/config --enable CONFIG_DRAM_ODT_EN
}
