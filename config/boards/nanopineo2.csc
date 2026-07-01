# Allwinner H5 quad core 256/512MB RAM SoC headless GBE
BOARD_NAME="NanoPi Neo 2"
BOARD_VENDOR="friendlyelec"
BOARDFAMILY="sun50iw2"
BOARD_MAINTAINER="spendist"
INTRODUCED="2017"
BOOTCONFIG="nanopi_neo2_defconfig"
MODULES="g_serial"
MODULES_BLACKLIST="lima"
DEFAULT_OVERLAYS="usbhost1 usbhost2"
DEFAULT_CONSOLE="serial"
SERIALCON="ttyS0,ttyGS0"
HAS_VIDEO_OUTPUT="no"
KERNEL_TARGET="current,edge,legacy"
KERNEL_TEST_TARGET="current"
CRUSTCONFIG="h5_defconfig"

function post_config_uboot_target__neo2_extra_configs() {
	display_alert "$BOARD" "u-boot: DRAM tune (504) + eMMC slot" "info"
	# Upstream nanopi_neo2_defconfig runs DRAM at an aggressive 672; pin the
	# Armbian-tuned 504 for stability on the v2026.07 family-default u-boot.
	run_host_command_logged scripts/config --set-val CONFIG_DRAM_CLK "504"
	# Enable the extra MMC slot (eMMC present on some NEO2 carriers). The old
	# board.c auto-DT-select (NEO2 v1.1) patch is dropped: its
	# CONFIG_BOOT_PROCESS_MULTI_DTB gate no longer exists in v2026.07, and the
	# kernel dtb (not u-boot) drives DT selection in the Armbian boot flow.
	run_host_command_logged scripts/config --set-val CONFIG_MMC_SUNXI_SLOT_EXTRA "2"
}
