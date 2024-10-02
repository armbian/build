# Allwinner A20 dual core 1Gb SoC 1xSATA
BOARD_NAME="Cubieboard 2"
BOARDFAMILY="sun7i"
BOARD_MAINTAINER=""
BOOTCONFIG="Cubieboard2_config"
KERNEL_TARGET="legacy,current,edge"
KERNEL_TEST_TARGET="current"

function post_config_uboot_target__extra_configs_for_cubieboard2() {
	display_alert "$BOARD" "set dram clock" "info"
	run_host_command_logged scripts/config --set-val CONFIG_DRAM_CLK "432"

	display_alert "$BOARD" "disable de2 to improve edid detection" "info"
	run_host_command_logged scripts/config --disable CONFIG_VIDEO_DE2

	display_alert "$BOARD" "add optional emmc" "info"
	run_host_command_logged scripts/config --set-val CONFIG_MMC_SUNXI_SLOT_EXTRA "2"
}
