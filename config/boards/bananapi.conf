# Allwinner A20 dual core 1Gb RAM SoC 1xSATA GBE
BOARD_NAME="Banana Pi"
BOARDFAMILY="sun7i"
BOARD_MAINTAINER="DylanHP janprunk"
BOOTCONFIG="Bananapi_defconfig"
KERNEL_TARGET="legacy,current,edge"
KERNEL_TEST_TARGET="current"

function post_config_uboot_target__extra_configs_for_bananapi() {
	display_alert "$BOARD" "set dram clock" "info"
	run_host_command_logged scripts/config --set-val CONFIG_DRAM_CLK "384"

	display_alert "$BOARD" "disable de2 to improve edid detection" "info"
	run_host_command_logged scripts/config --disable CONFIG_VIDEO_DE2
}
