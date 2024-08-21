# Allwinner A20 dual core 1GB RAM SoC eMMC GBE 1xSATA
BOARD_NAME="A20 OLinuXino Lime 2"
BOARDFAMILY="sun7i"
BOARD_MAINTAINER=""
BOOTCONFIG="A20-OLinuXino-Lime2-eMMC_defconfig"
KERNEL_TARGET="legacy,current,edge"
KERNEL_TEST_TARGET="current"

function post_config_uboot_target__extra_configs_for_lime2() {
	run_host_command_logged scripts/config --enable CONFIG_PHY_MICREL
	run_host_command_logged scripts/config --enable CONFIG_PHY_MICREL_KSZ90X1
}
