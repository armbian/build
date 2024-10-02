# Allwinner H5 quad core 2GB SoC eMMC
BOARD_NAME="Tritium"
BOARDFAMILY="sun50iw2"
BOARD_MAINTAINER="Tonymac32"
BOOTCONFIG="libretech_all_h3_cc_h5_defconfig"
MODULES_CURRENT="g_serial"
DEFAULT_OVERLAYS="analog-codec"
SERIALCON="ttyS0,ttyGS0"
KERNEL_TARGET="legacy,current,edge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
CRUSTCONFIG="h5_defconfig"

function post_config_uboot_target__lower_DRAM_freq_for_Tritium_H5() {
	display_alert "$BOARD" "The defconfig file of Tritium H5 explicitly defines DRAM_CLK as 672." "info"
	display_alert "$BOARD" "Change to match default value used for H5 SoC in Armbian" "info"
	run_host_command_logged scripts/config --set-val CONFIG_DRAM_CLK "648"
}
