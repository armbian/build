# Allwinner A64 quad core 1GB RAM SoC GBE eMMC Wi-Fi/BT
BOARD_NAME="A64 OLinuXino"
BOARDFAMILY="sun50iw1"
BOARD_MAINTAINER=""
BOOTCONFIG_DEFAULT="sun50iw1p1_config"
BOOTCONFIG="a64-olinuxino_defconfig"
KERNEL_TARGET="legacy,current,edge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
CRUSTCONFIG="a64_defconfig"

function post_config_uboot_target__extra_configs_for_orangepi_mini() {
	display_alert "$BOARD" "set dram clock" "info"
	run_host_command_logged scripts/config --set-val CONFIG_DRAM_CLK "624"
	run_host_command_logged scripts/config --set-val CONFIG_DRAM_ZQ "3881949"
}
