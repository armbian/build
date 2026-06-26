# Allwinner A733 octa core 2-16GB RAM GBE USB3 WiFi/BT NVMe eMMC
BOARD_NAME="Orange Pi 4 Pro"
INTRODUCED="2025"
BOOT_FDT_FILE="allwinner/sun60i-a733-orangepi-4-pro.dtb"
SUNXI_BOOT0_SDCARD_FEX="${SRC}/packages/blobs/sunxi/sun60iw2/boot0_sdcard_orangepi4pro.fex"
SUNXI_BOOT0_SPINOR_FEX="${SRC}/packages/blobs/sunxi/sun60iw2/boot0_spinor_orangepi4pro.fex"
BOARD_MAINTAINER="shkolnik"

source "${SRC}/config/sources/vendors/xunlong/sun60iw2-a733-common.inc"

# The 4 Pro has 16 MB SPI-NOR; support writing the bootloader to MTD (the SD
# writer and blob fetch are shared in the common include).
function write_uboot_platform_mtd() {
	local SCRIPT_DIR="$1"   # dir holding boot0_spinor.fex + boot_package.fex
	flash_erase /dev/mtd0 0 0
	mtd_debug write /dev/mtd0 0      "$(stat -c%s "$SCRIPT_DIR/boot0_spinor.fex")" "$SCRIPT_DIR/boot0_spinor.fex"
	mtd_debug write /dev/mtd0 262144 "$(stat -c%s "$SCRIPT_DIR/boot_package.fex")" "$SCRIPT_DIR/boot_package.fex"
	sync
}
