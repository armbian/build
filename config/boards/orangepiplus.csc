# Allwinner H3 quad core 1GB/2GB RAM WiFi eMMC
BOARD_NAME="Orange Pi+"
BOARDFAMILY="sun8i"
BOARD_MAINTAINER=""
BOOTCONFIG="orangepi_plus_defconfig"
KERNEL_TARGET="legacy,current,edge"

function post_config_uboot_target__extra_configs_for_orangepi_plus() {
	display_alert "$BOARD" "set dram clock" "info"
	run_host_command_logged scripts/config --set-val CONFIG_DRAM_CLK "624"
	run_host_command_logged scripts/config --set-val CONFIG_DRAM_ZQ "3881979"
	run_host_command_logged scripts/config --enable CONFIG_DRAM_ODT_EN
}
