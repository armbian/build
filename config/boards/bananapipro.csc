# Allwinner A20 dual core 1GB RAM SoC 1xSATA GBE Wifi
BOARD_NAME="Banana Pi Pro"
BOARDFAMILY="sun7i"
BOARD_MAINTAINER=""
BOOTCONFIG="Bananapro_defconfig"
KERNEL_TARGET="legacy,current,edge"
KERNEL_TEST_TARGET="current"

function post_config_uboot_target__extra_configs_for_bananapipro() {
	display_alert "$BOARD" "set dram clock" "info"
	run_host_command_logged scripts/config --set-val CONFIG_DRAM_CLK "384"
}
