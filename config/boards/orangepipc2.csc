# Allwinner H5 quad core 1GB RAM SoC GBE SPI
BOARD_NAME="Orange Pi PC2"
BOARDFAMILY="sun50iw2"
BOARD_MAINTAINER=""
BOOTCONFIG="orangepi_pc2_defconfig"
KERNEL_TARGET="legacy,current,edge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
CRUSTCONFIG="h5_defconfig"

function post_config_uboot_target__extra_configs_for_orangepi_pc2() {
	display_alert "$BOARD" "set dram clock" "info"
	run_host_command_logged scripts/config --set-val CONFIG_DRAM_CLK "504"
	run_host_command_logged scripts/config --enable CONFIG_DRAM_ODT_EN
}
