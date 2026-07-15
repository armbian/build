# Allwinner H5 quad core 2GB RAM Wi-Fi/BT
BOARD_NAME="Orange Pi Prime"
BOARD_VENDOR="xunlong"
BOARDFAMILY="sun50iw2"
BOARD_MAINTAINER=""
INTRODUCED="2016"
BOOTCONFIG="orangepi_prime_defconfig"
DEFAULT_OVERLAYS="analog-codec"
KERNEL_TARGET="current,edge,legacy"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
CRUSTCONFIG="orangepi_pc2_defconfig"

function post_config_uboot_target__extra_configs_for_orangepi_prime() {
	display_alert "$BOARD" "u-boot: DRAM tune (504/ODT) + SPI-flash boot" "info"
	# Upstream orangepi_prime_defconfig runs DRAM at an aggressive 672; pin the
	# Armbian-tuned 504 + ODT for stability (v2026.07 family default u-boot).
	run_host_command_logged scripts/config --set-val CONFIG_DRAM_CLK "504"
	run_host_command_logged scripts/config --enable CONFIG_DRAM_ODT_EN
	# Allow booting from the on-board SPI flash (not in the upstream defconfig).
	# Safe on H5 (the SPL_SPI A64 SPL-boot regression does not affect sun50iw2).
	# CONFIG_MACPWR (old eth PHY power GPIO) is gone in v2026.07 - the PHY rail is
	# now driven from the DT, so it is intentionally not re-added.
	run_host_command_logged scripts/config --enable CONFIG_SPL_SPI_SUNXI
}
