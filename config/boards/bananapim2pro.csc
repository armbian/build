# Amlogic S905X3 quad core 2-4GB RAM SoC eMMC GBE USB3 SPI Wifi
BOARD_NAME="Banana Pi M2Pro"
BOARDFAMILY="meson-sm1"
BOARD_MAINTAINER=""
BOOTCONFIG="bananapi-m5_defconfig" # u-boot is still shared betwen m5 and m2pro
BOOT_FDT_FILE="amlogic/meson-sm1-bananapi-m2-pro.dtb"
KERNEL_TARGET="edge" # current does not carry the DTB yet; @TODO re-add when 6.2+ is current for meson64
FULL_DESKTOP="yes"
SERIALCON="ttyAML0"
BOOT_LOGO="desktop"
BOOTBRANCH_BOARD="tag:v2022.10"
BOOTPATCHDIR="v2022.10"
