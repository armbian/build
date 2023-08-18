# Amlogic S905X3 quad core 2-4GB RAM SoC eMMC GBE USB3 SPI Wifi
BOARD_NAME="Banana Pi M2Pro"
BOARDFAMILY="meson-sm1"
BOARD_MAINTAINER=""
BOOTCONFIG="bananapi-m2-pro_defconfig"
BOOT_FDT_FILE="amlogic/meson-sm1-bananapi-m2-pro.dtb"
KERNEL_TARGET="current,edge"
FULL_DESKTOP="yes"
SERIALCON="ttyAML0"
BOOT_LOGO="desktop"
BOOTBRANCH_BOARD="tag:v2023.07.02"
BOOTPATCHDIR="v2023.07.02"

function fetch_sources_tools__libreelec_amlogic_fip_pre_m2-pro_blob_update() {
        fetch_from_repo "https://github.com/Dangku/amlogic-boot-fip" "amlogic-boot-fip" "branch:master"
}

function post_uboot_custom_postprocess__bpi-m2-pro() {
	uboot_g12_postprocess "$SRC"/cache/sources/amlogic-boot-fip/bananapi-m2-pro g12a
}
