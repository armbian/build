# Allwinner A20 dual core 1Gb SoC
BOARD_NAME="pcDuino 3"
BOARDFAMILY="sun7i"
BOARD_MAINTAINER=""
BOOTCONFIG="Linksprite_pcDuino3_defconfig"
KERNEL_TARGET="legacy,current,edge"
KERNEL_TEST_TARGET="current"

function post_config_uboot_target__extra_configs_for_pcDuino3() {
	display_alert "$BOARD" "set dram clock" "info"
	run_host_command_logged scripts/config --set-val CONFIG_DRAM_CLK "408"
}
