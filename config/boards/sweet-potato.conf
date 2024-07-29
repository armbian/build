# Amlogic S905x quad core 2Gb RAM SoC eMMC SPI
BOARD_NAME="Sweet Potato"
BOARDFAMILY="meson-gxl"
BOARD_MAINTAINER="Tonymac32"
BOOTCONFIG="libretech-cc_v2_defconfig"
BOOT_FDT_FILE="amlogic/meson-gxl-s905x-libretech-cc-v2.dtb"
KERNEL_TARGET="current,edge"
FULL_DESKTOP="yes"
ASOUND_STATE="asound.state.mesongx"
BOOT_LOGO="desktop"

function post_family_config__declare_u-boot-version() {
	BOOTBRANCH='tag:v2024.04'
	BOOTPATCHDIR='v2024.04'
}
