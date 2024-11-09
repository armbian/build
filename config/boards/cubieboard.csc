# Allwinner A10 single core 1Gb SoC 1xSATA
BOARD_NAME="Cubieboard 1"
BOARDFAMILY="sun4i"
BOARD_MAINTAINER=""
BOOTCONFIG="Cubieboard_config"
HAS_VIDEO_OUTPUT="no"
KERNEL_TARGET="legacy,current,edge"
KERNEL_TEST_TARGET="current"
MODULES_BLACKLIST="ir_lirc_codec lirc_dev sunxi-cir"

function post_config_uboot_target__extra_configs_for_cubieboard() {
	display_alert "$BOARD" "set dram clock" "info"
	run_host_command_logged scripts/config --set-val CONFIG_DRAM_CLK "432"

	display_alert "$BOARD" "disable de2 to improve edid detection" "info"
	run_host_command_logged scripts/config --disable CONFIG_VIDEO_DE2
}
